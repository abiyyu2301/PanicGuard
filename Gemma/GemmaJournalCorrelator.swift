import Foundation
import HealthKit
import EventKit

// MARK: - Gemma Journal Correlator
/// Reads 90-day episode history + journal entries + calendar + sleep data
/// and uses Gemma to identify trigger correlations.
final class GemmaJournalCorrelator: ObservableObject {

    // MARK: - Dependencies

    private let gemmaService = GemmaServiceLiteRT.shared
    private let episodeLogger = EpisodeLogger()
    private let healthKitService = HealthKitService.shared
    private let eventStore = EKEventStore()

    // MARK: - Analysis Window

    private static let analysisWindowDays = 90

    // MARK: - Calendar Tag Prefix

    /// Events with this prefix in the title are treated as trigger events.
    /// e.g. "[PG-work] quarterly review"
    private static let calendarTagPrefix = "[PG-"

    // MARK: - Public Interface

    /// Analyzes a new journal entry against 90-day history and returns
    /// Gemma's summary and insights.
    /// Also updates the correlation store with any newly identified patterns.
    func analyzeJournalEntry(_ entry: EpisodeLogger.JournalEntry) async -> (summary: String?, insights: [String]) {
        let context = await buildAnalysisContext()

        guard !context.isEmpty else {
            return (nil, [])
        }

        let prompt = Self.PromptTemplates.journalAnalysis(entry: entry, context: context)
        let response = await callGemma(prompt: prompt)

        // Parse and store correlations
        if let correlations = response.correlations {
            for correlation in correlations {
                if let triggerCorrelation = correlation.toTriggerCorrelation() {
                    try? episodeLogger.insert(triggerCorrelation)
                }
            }
        }

        return (response.summary, response.insights)
    }

    /// Performs a full re-analysis of all 90-day data,
    /// updating all correlations in the store.
    /// Called periodically or when user requests a refresh.
    func runFullAnalysis() async -> [EpisodeLogger.TriggerCorrelation] {
        let context = await buildAnalysisContext()

        guard !context.isEmpty else {
            return []
        }

        let prompt = Self.PromptTemplates.fullAnalysis(context: context)
        let response = await callGemma(prompt: prompt)

        if let correlations = response.correlations {
            for correlation in correlations {
                if let triggerCorrelation = correlation.toTriggerCorrelation() {
                    try? episodeLogger.insert(triggerCorrelation)
                }
            }
            return correlations.compactMap { $0.toTriggerCorrelation() }
        }

        return []
    }

    // MARK: - Context Building

    /// Builds the multi-part analysis context from all data sources.
    private func buildAnalysisContext() async -> AnalysisContext {
        async let episodes = fetchEpisodeHistory()
        async let journalEntries = fetchJournalHistory()
        async let sleepData = fetchSleepData()
        async let calendarEvents = fetchCalendarEvents()

        return AnalysisContext(
            episodes: episodes,
            journalEntries: journalEntries,
            sleepData: sleepData,
            calendarEvents: calendarEvents
        )
    }

    // MARK: - Data Fetching

    private func fetchEpisodeHistory() -> [EpisodeHistoryEntry] {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.analysisWindowDays,
            to: Date()
        ) ?? Date()

        let episodes = (try? episodeLogger.queryEpisodes(from: startDate, to: Date())) ?? []

        return episodes.map { episode in
            EpisodeHistoryEntry(
                id: episode.id,
                timestamp: episode.detectedAt,
                durationMinutes: episode.episodeDuration / 60.0,
                confidence: episode.confidence,
                escalated: episode.escalationTriggered,
                resolution: episode.resolvedAs.rawValue
            )
        }
    }

    private func fetchJournalHistory() -> [EpisodeLogger.JournalEntry] {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.analysisWindowDays,
            to: Date()
        ) ?? Date()
        return (try? episodeLogger.queryJournalEntries(from: startDate, to: Date())) ?? []
    }

    private func fetchSleepData() -> [SleepDataPoint] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let sleepType = HKQuantityType.categoryType(forIdentifier: .sleepAnalysis)!
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.analysisWindowDays,
            to: Date()
        ) ?? Date()

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let dataPoints = (samples as? [HKCategorySample])?.map { sample in
                    let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    return SleepDataPoint(date: sample.startDate, hours: hours)
                } ?? []
                continuation.resume(returning: dataPoints)
            }
            self.healthKitService.performQuery(query)
        }
    }

    private func fetchCalendarEvents() -> [CalendarTrigger] {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.analysisWindowDays,
            to: Date()
        ) ?? Date()

        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: Date(),
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)

        return events.compactMap { event -> CalendarTrigger? in
            guard let title = event.title,
                  let range = title.range(of: Self.calendarTagPrefix) else {
                return nil
            }

            let afterPrefix = title[range.upperBound...]
            guard let endBracket = afterPrefix.firstIndex(of: "]") else {
                return nil
            }

            let category = String(afterPrefix[..<endBracket])
            let cleanTitle = title.replacingOccurrences(of: Self.calendarTagPrefix + category + "] ", with: "")

            return CalendarTrigger(
                title: cleanTitle,
                date: event.startDate,
                category: CalendarTriggerCategory(rawValue: category) ?? .other
            )
        }
    }

    // MARK: - Gemma Inference

    private func callGemma(prompt: String) async -> GemmaCorrelationResponse {
        // Build full prompt with system instructions
        let fullPrompt = """
        \(Self.systemPrompt)

        \(prompt)

        Respond with ONLY valid JSON in the following format. Do not include any text outside the JSON object.
        {
            "summary": "<one sentence summary of journal entry significance>",
            "insights": ["<insight 1>", "<insight 2>", "<insight 3>"],
            "correlations": [
                {
                    "pattern_type": "<timeOfDay|calendarEvent|sleepDebt|journalTheme|exerciseContext|none>",
                    "pattern_description": "<natural language description of the pattern>",
                    "confidence": <0.0 to 1.0>,
                    "episode_count": <integer>,
                    "supporting_details": "<specific details about matching episodes>"
                }
            ]
        }
        """

        // Run inference via GemmaService
        let jsonResponse = await gemmaService.runJournalCorrelatorInference(prompt: fullPrompt)

        return parseCorrelationResponse(jsonResponse)
    }

    private func parseCorrelationResponse(_ jsonString: String) -> GemmaCorrelationResponse {
        let cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            return GemmaCorrelationResponse(summary: nil, insights: [], correlations: nil)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(GemmaCorrelationResponse.self, from: data)
        } catch {
            return extractFieldsFromPartialResponse(cleaned)
        }
    }

    private func extractFieldsFromPartialResponse(_ string: String) -> GemmaCorrelationResponse {
        var summary: String?
        var insights: [String] = []
        var correlations: [CorrelationPayload]?

        // Extract summary
        if let sumRange = string.range(of: "\"summary\""),
           let colon = string[sumRange.upperBound...].firstIndex(of: ":") {
            var value = String(string[colon.dropFirst(1)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") { value = String(value.dropFirst()) }
            if let endQuote = value.firstIndex(of: "\"") {
                summary = String(value[..<endQuote])
            }
        }

        // Extract insights array
        if let openBracket = string.firstIndex(of: "["),
           let closeBracket = string.lastIndex(of: "]") {
            let arrayStr = String(string[openBracket...closeBracket])
            let pattern = #"([^"]+)"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = arrayStr as NSString
                let results = regex.matches(in: arrayStr, range: NSRange(location: 0, length: nsString.length))
                insights = results.compactMap { result in
                    guard result.numberOfRanges >= 2 else { return nil }
                    return nsString.substring(with: result.range(at: 1))
                }
            }
        }

        return GemmaCorrelationResponse(
            summary: summary,
            insights: insights,
            correlations: correlations
        )
    }

    // MARK: - System Prompt

    private static let systemPrompt = """
    You are PanicGuard's correlation analysis engine. Your role is to analyze patterns
    across a user's panic episodes, journal entries, sleep data, and calendar events
    to identify meaningful triggers and correlations.

    You have access to:
    - Up to 90 days of panic episode data (timestamps, duration, confidence, resolution)
    - Journal entries (free-text + emotional tags: anxious, stressed, okay, calm)
    - Sleep duration data (hours per night)
    - Calendar events tagged with trigger categories: work, social, therapy, exercise, travel

    ANALYSIS GUIDELINES:
    - Look for temporal patterns: time of day, day of week, clustering after specific events
    - Cross-reference episodes with sleep debt: episodes after <6h sleep are significant
    - Cross-reference episodes with calendar: events near episodes
    - Cross-reference episodes with emotional tags: anxious/stressed tags preceding episodes
    - Only report correlations with confidence >= 0.6
    - Each correlation must be grounded in specific episode data

    OUTPUT FORMAT: Respond ONLY with a JSON object matching the schema provided.
    """
}

// MARK: - Prompt Templates

extension GemmaJournalCorrelator {

    enum PromptTemplates {

        static func journalAnalysis(
            entry: EpisodeLogger.JournalEntry,
            context: AnalysisContext
        ) -> String {
            var prompt = "JOURNAL ENTRY TO ANALYZE:\n"
            prompt += "  id: \(entry.id)\n"
            prompt += "  timestamp: \(formatDate(entry.timestamp))\n"
            prompt += "  content: \"\(entry.content)\"\n"
            prompt += "  emotional_tags: [\(entry.emotionalTags.joined(separator: ", "))]\n"
            if let episodeId = entry.linkedEpisodeId {
                prompt += "  linked_episode_id: \(episodeId)\n"
            }

            prompt += "\n90-DAY EPISODE HISTORY:\n"
            if context.episodes.isEmpty {
                prompt += "  (no episodes in this window)\n"
            } else {
                for ep in context.episodes.prefix(50) {
                    prompt += "  - \(formatDate(ep.timestamp)) | \(String(format: "%.0f", ep.durationMinutes))min | conf \(String(format: "%.2f", ep.confidence)) | \(ep.resolution)\n"
                }
                if context.episodes.count > 50 {
                    prompt += "  ... and \(context.episodes.count - 50) more episodes\n"
                }
            }

            prompt += "\nJOURNAL ENTRIES (last 90 days):\n"
            if context.journalEntries.isEmpty {
                prompt += "  (no journal entries in this window)\n"
            } else {
                for je in context.journalEntries.prefix(20) {
                    prompt += "  - \(formatDate(je.timestamp)): \"\(je.content.prefix(100))\" [\(je.emotionalTags.joined(separator: ","))]\n"
                }
            }

            prompt += "\nSLEEP DATA:\n"
            prompt += formatSleepData(context.sleepData, episodes: context.episodes)

            prompt += "\nCALENDAR EVENTS (tagged [PG-category]):\n"
            if context.calendarEvents.isEmpty {
                prompt += "  (no tagged calendar events)\n"
            } else {
                for ce in context.calendarEvents.prefix(20) {
                    prompt += "  - \(formatDate(ce.date)) [\(ce.category.rawValue)]: \(ce.title)\n"
                }
            }

            prompt += "\nBased on this data, identify any trigger correlations relevant to today's journal entry."
            return prompt
        }

        static func fullAnalysis(context: AnalysisContext) -> String {
            var prompt = "FULL 90-DAY TRIGGER CORRELATION ANALYSIS\n"

            prompt += "\nEPISODE SUMMARY:\n"
            prompt += "  Total episodes: \(context.episodes.count)\n"
            if let avgDuration = context.episodes.map({ $0.durationMinutes }).average {
                prompt += "  Average duration: \(String(format: "%.1f", avgDuration)) min\n"
            }
            let escalatedCount = context.episodes.filter { $0.escalated }.count
            prompt += "  Escalated: \(escalatedCount)\n"

            prompt += "\nEPISODE TIMING PATTERNS:\n"
            prompt += formatTimePatterns(context.episodes)

            prompt += "\nSLEEP ANALYSIS:\n"
            prompt += formatSleepData(context.sleepData, episodes: context.episodes)

            prompt += "\nCALENDAR EVENTS:\n"
            if context.calendarEvents.isEmpty {
                prompt += "  (no tagged events)\n"
            } else {
                for ce in context.calendarEvents.prefix(30) {
                    prompt += "  - \(formatDate(ce.date)) [\(ce.category.rawValue)]: \(ce.title)\n"
                }
            }

            prompt += "\nJOURNAL THEMES:\n"
            let allTags = context.journalEntries.flatMap { $0.emotionalTags }
            let tagCounts = Dictionary(grouping: allTags, by: { $0 }).mapValues { $0.count }
            for (tag, count) in tagCounts.sorted(by: { $0.value > $1.value }) {
                prompt += "  \(tag): \(count) entries\n"
            }

            prompt += "\nIdentify ALL significant trigger correlations (confidence >= 0.6) across this 90-day window."
            return prompt
        }

        private static func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }

        private static func formatTimePatterns(_ episodes: [EpisodeHistoryEntry]) -> String {
            guard !episodes.isEmpty else { return "  (no data)\n" }

            let hourCounts = Dictionary(grouping: episodes) {
                Calendar.current.component(.hour, from: $0.timestamp)
            }.mapValues { $0.count }

            var result = "  Episodes by hour:\n"
            for hour in 0..<24 {
                let count = hourCounts[hour] ?? 0
                if count > 0 {
                    result += "    \(String(format: "%02d", hour)):00 - \(count) episode\(count == 1 ? "" : "s")\n"
                }
            }
            return result
        }

        private static func formatSleepData(_ sleepData: [SleepDataPoint], episodes: [EpisodeHistoryEntry]) -> String {
            guard !sleepData.isEmpty else { return "  (no sleep data)\n" }

            var result = ""
            let avgSleep = sleepData.map { $0.hours }.reduce(0, +) / Double(max(1, sleepData.count))
            result += "  Average sleep: \(String(format: "%.1f", avgSleep)) hours/night\n"

            let lowSleepNights = sleepData.filter { $0.hours < 6.0 }
            result += "  Nights with <6h sleep: \(lowSleepNights.count)\n"

            let episodeDates = Set(episodes.map { Calendar.current.startOfDay(for: $0.timestamp) })
            let sleepBeforeEpisodes = sleepData.filter { sleep in
                let nightBefore = Calendar.current.date(byAdding: .day, value: -1, to: sleep.date) ?? sleep.date
                return episodeDates.contains(Calendar.current.startOfDay(for: nightBefore))
            }
            if !sleepBeforeEpisodes.isEmpty {
                let avgBefore = sleepBeforeEpisodes.map { $0.hours }.reduce(0, +) / Double(sleepBeforeEpisodes.count)
                result += "  Avg sleep night before episodes: \(String(format: "%.1f", avgBefore)) hours\n"
            }

            return result
        }
    }
}

// MARK: - Supporting Types

struct AnalysisContext {
    let episodes: [EpisodeHistoryEntry]
    let journalEntries: [EpisodeLogger.JournalEntry]
    let sleepData: [SleepDataPoint]
    let calendarEvents: [CalendarTrigger]
    var isEmpty: Bool { episodes.isEmpty && journalEntries.isEmpty && sleepData.isEmpty && calendarEvents.isEmpty }
}

struct EpisodeHistoryEntry {
    let id: UUID
    let timestamp: Date
    let durationMinutes: Double
    let confidence: Double
    let escalated: Bool
    let resolution: String
}

struct SleepDataPoint {
    let date: Date
    let hours: Double
}

struct CalendarTrigger {
    let title: String
    let date: Date
    let category: CalendarTriggerCategory
}

enum CalendarTriggerCategory: String {
    case work
    case social
    case therapy
    case exercise
    case travel
    case other
}

struct CorrelationPayload: Codable {
    let patternType: String
    let patternDescription: String
    let confidence: Double
    let episodeCount: Int
    let supportingDetails: String

    func toTriggerCorrelation() -> EpisodeLogger.TriggerCorrelation? {
        let type: EpisodeLogger.TriggerCorrelation.PatternType
        switch patternType.lowercased() {
        case "timeofday", "time_of_day":
            type = .timeOfDay
        case "calendarevent", "calendar_event":
            type = .calendarEvent
        case "sleepdebt", "sleep_debt":
            type = .sleepDebt
        case "journaltheme", "journal_theme":
            type = .journalTheme
        case "exercisecontext", "exercise_context":
            type = .exerciseContext
        default:
            type = .none
        }

        return EpisodeLogger.TriggerCorrelation(
            id: UUID(),
            patternType: type,
            patternDescription: patternDescription,
            confidence: confidence,
            episodeCount: episodeCount,
            supportingDetails: supportingDetails,
            lastUpdated: Date(),
            isActive: true
        )
    }
}

struct GemmaCorrelationResponse: Codable {
    let summary: String?
    let insights: [String]
    let correlations: [CorrelationPayload]?
}

// MARK: - HealthKit Extension for Query Execution

private extension HealthKitService {
    /// Executes an HKSampleQuery using the shared singleton's authorized HealthKit store.
    func performQuery(_ query: HKSampleQuery) {
        healthStore.execute(query)
    }
}
// MARK: - Array Average Helper

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
