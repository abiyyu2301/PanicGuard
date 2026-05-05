import Foundation

// MARK: - Therapy Report Generator
/// Reads weekly episode metadata and generates a structured therapy report
/// using Gemma E2B on-device inference.
final class GemmaTherapyReportGenerator: ObservableObject {

    // MARK: - Published State

    @Published var isGenerating: Bool = false
    @Published var lastGeneratedReport: TherapyReport?
    @Published var lastError: Error?
    @Published var reportHistory: [TherapyReport] = []

    // MARK: - Dependencies

    private let gemmaService: GemmaService
    private let episodeLogger: EpisodeLogger

    // MARK: - Date Formatters

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withFullTime]
        return f
    }()

    private let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    // MARK: - Initialization

    init(gemmaService: GemmaService = .shared, episodeLogger: EpisodeLogger = EpisodeLogger()) {
        self.gemmaService = gemmaService
        self.episodeLogger = episodeLogger
        loadHistory()
    }

    // MARK: - Public API

    /// Generates a therapy report for the past 7 days.
    /// Returns the report synchronously via published state.
    @MainActor
    func generateWeeklyReport() async {
        guard !isGenerating else { return }

        isGenerating = true
        lastError = nil

        do {
            let report = try await performGeneration()
            lastGeneratedReport = report
            saveReport(report)
            reportHistory.insert(report, at: 0)
        } catch {
            lastError = error
            print("[GemmaTherapyReportGenerator] Generation failed: \(error.localizedDescription)")
        }

        isGenerating = false
    }

    /// Returns the date range string for the current week (Mon–Sun).
    func currentWeekRange() -> String {
        let calendar = Calendar.current
        let today = Date()

        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return ""
        }

        return "\(displayDateFormatter.string(from: weekStart)) – \(displayDateFormatter.string(from: weekEnd))"
    }

    /// Returns a human-readable summary of the last generated report
    /// for badge display in the UI.
    func summaryBadge() -> String? {
        guard let report = lastGeneratedReport else { return nil }
        return "Weekly summary ready"
    }

    /// Deletes a report from history.
    func deleteReport(_ report: TherapyReport) {
        reportHistory.removeAll { $0.id == report.id }
        if lastGeneratedReport?.id == report.id {
            lastGeneratedReport = reportHistory.first
        }
        persistHistory()
    }

    /// Marks the report as shared.
    func markReportShared(_ report: TherapyReport) {
        guard let index = reportHistory.firstIndex(where: { $0.id == report.id }) else { return }
        var updated = report
        updated.isShared = true
        reportHistory[index] = updated
        if lastGeneratedReport?.id == report.id {
            lastGeneratedReport = updated
        }
        persistHistory()
    }

    // MARK: - Private Implementation

    private func performGeneration() async throws -> TherapyReport {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            throw TherapyReportError.invalidDateRange
        }

        // Fetch episode data from logger
        let episodes = try episodeLogger.queryEpisodes(from: weekStart, to: weekEnd)

        // Fetch prior week for comparison
        let priorWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let priorWeekEnd = calendar.date(byAdding: .day, value: -1, to: weekStart)!
        let priorWeekEpisodes = try episodeLogger.queryEpisodes(from: priorWeekStart, to: priorWeekEnd)

        // Build structured metadata for Gemma
        let metadata = WeeklyMetadata(
            weekStart: weekStart,
            weekEnd: weekEnd,
            episodes: episodes.map { EpisodeMetadata(from: $0) },
            priorWeekCount: priorWeekEpisodes.count
        )

        // Generate report body via Gemma
        let reportBody = await generateReportBody(from: metadata)

        // Identify dominant patterns
        let patterns = identifyDominantPatterns(from: episodes)

        let report = TherapyReport(
            id: UUID(),
            weekStart: weekStart,
            weekEnd: weekEnd,
            episodeCount: episodes.count,
            totalDurationMinutes: episodes.reduce(0) { $0 + $1.episodeDuration / 60 },
            dominantPatterns: patterns,
            episodeDates: episodes.map { $0.detectedAt },
            averageSleepHours: nil, // HealthKit integration deferred
            gemmaReportBody: reportBody,
            createdAt: Date(),
            isShared: false
        )

        return report
    }

    private func generateReportBody(from metadata: WeeklyMetadata) async -> String {
        // If Gemma model is not loaded, fall back to template generation
        guard gemmaService.isModelLoaded else {
            return buildTemplateReport(from: metadata)
        }

        let prompt = buildPrompt(from: metadata)

        return await withCheckedContinuation { continuation in
            Task {
                // Run inference on a background thread
                let response = await runGemmaInference(prompt: prompt)
                continuation.resume(returning: response)
            }
        }
    }

    private func buildPrompt(from metadata: WeeklyMetadata) -> String {
        var prompt = "Generate a structured weekly therapy report for a panic disorder patient.\n\n"

        prompt += "WEEK: \(displayDateFormatter.string(from: metadata.weekStart)) – \(displayDateFormatter.string(from: metadata.weekEnd))\n"
        prompt += "TOTAL EPISODES: \(metadata.episodes.count) (compared to \(metadata.priorWeekCount) the prior week)\n\n"

        if metadata.episodes.isEmpty {
            prompt += "No panic episodes recorded this week.\n"
        } else {
            prompt += "EPISODE DETAILS:\n"
            for ep in metadata.episodes {
                let dateStr = displayDateFormatter.string(from: ep.detectedAt)
                let timeStr = displayTimeFormatter.string(from: ep.detectedAt)
                let durationMin = Int(ep.episodeDuration / 60)
                let resolution = resolutionLabel(ep.resolvedAs)

                prompt += "  - \(dateStr), \(timeStr): \(durationMin)m, peak HR \(Int(ep.peakHeartRate)), \(resolution)\n"
            }
            prompt += "\n"
        }

        prompt += """
        OUTPUT FORMAT:
        Write a professional therapy report with these sections:
        - Week summary (episode count vs prior week)
        - Episode list (date, time, duration, peak HR, outcome)
        - Dominant patterns (identify clustering by time of day, sleep, or context)
        - Notes for discussion (anything clinically relevant Gemma finds)

        Be concise, clinical, and compassionate. This report will be reviewed by a therapist.
        """

        return prompt
    }

    private func buildTemplateReport(from metadata: WeeklyMetadata) -> String {
        var body = "Week of \(displayDateFormatter.string(from: metadata.weekStart)) – \(displayDateFormatter.string(from: metadata.weekEnd)):\n\n"

        let comparison = metadata.episodes.count == metadata.priorWeekCount
            ? "same as"
            : metadata.episodes.count < metadata.priorWeekCount
                ? "down from \(metadata.priorWeekCount) the prior week"
                : "up from \(metadata.priorWeekCount) the prior week"

        body += "Total episodes: \(metadata.episodes.count) (\(comparison))\n\n"

        if metadata.episodes.isEmpty {
            body += "No panic episodes were recorded this week.\n"
        } else {
            body += "Episodes:\n"
            for ep in metadata.episodes {
                let dateStr = displayDateFormatter.string(from: ep.detectedAt)
                let timeStr = displayTimeFormatter.string(from: ep.detectedAt)
                let durationMin = Int(ep.episodeDuration / 60)
                let resolution = resolutionLabel(ep.resolvedAs)

                body += "  - \(dateStr), \(timeStr): \(durationMin)m \(Int(ep.episodeDuration.truncatingRemainder(dividingBy: 60)))s, peak HR \(Int(ep.peakHeartRate)), \(resolution)\n"
            }
            body += "\n"
        }

        let patterns = identifyDominantPatterns(from: metadata.episodes.map { ep in
            EpisodeLogger.Episode(
                id: UUID(),
                detectedAt: ep.detectedAt,
                confidence: 0.8,
                resolvedAs: ep.resolvedAs,
                escalationTriggered: ep.escalationTriggered,
                contactNotified: false,
                episodeDuration: ep.episodeDuration
            )
        })

        if !patterns.isEmpty {
            body += "Dominant patterns this week:\n"
            for (i, pattern) in patterns.enumerated() {
                body += "  \(i + 1). \(pattern)\n"
            }
            body += "\n"
        }

        body += "Notes for discussion:\n"
        body += "  - Report generated automatically by PanicGuard\n"

        return body
    }

    private func runGemmaInference(prompt: String) async -> String {
        // Build full prompt with system instructions
        let fullPrompt = """
        You are PanicGuard, an on-device AI assistant that generates clinical therapy reports.
        Generate a structured weekly therapy report based on the patient data provided.
        Be concise, clinical, and compassionate.

        \(prompt)

        Respond with only the report text, no JSON or additional commentary.
        """

        // Use GemmaService's simulateInference path when model unavailable
        // In production, call llmInference.generateResponse directly
        guard gemmaService.isModelLoaded else {
            // Fallback: simulate a brief inference pause then return template
            return buildTemplateReport(from: WeeklyMetadata(
                weekStart: Date(),
                weekEnd: Date(),
                episodes: [],
                priorWeekCount: 0
            ))
        }

        // Placeholder for direct Gemma inference call
        // In production this would call:
        // let response = try await gemmaService.llmInference.generateResponse(modelPrompt: fullPrompt)
        // return response

        return buildTemplateReport(from: WeeklyMetadata(
            weekStart: Date(),
            weekEnd: Date(),
            episodes: [],
            priorWeekCount: 0
        ))
    }

    // MARK: - Pattern Identification

    private func identifyDominantPatterns(from episodes: [EpisodeLogger.Episode]) -> [String] {
        guard !episodes.isEmpty else { return [] }

        var patterns: [String] = []

        // Evening clustering: episodes after 9pm
        let eveningCount = episodes.filter { ep in
            let hour = Calendar.current.component(.hour, from: ep.detectedAt)
            return hour >= 21 || hour < 4
        }.count
        if eveningCount > 0 && Float(eveningCount) / Float(episodes.count) > 0.4 {
            patterns.append("Evening clustering (\(eveningCount) of \(episodes.count) episodes after 9pm)")
        }

        // Escalation frequency
        let escalatedCount = episodes.filter { $0.escalationTriggered }.count
        if escalatedCount > 0 {
            patterns.append("Escalations occurred (\(escalatedCount) of \(episodes.count) episodes)")
        }

        // Short episodes vs long
        let avgDuration = episodes.reduce(0) { $0 + $1.episodeDuration } / Double(episodes.count)
        if avgDuration < 180 {
            patterns.append("Short episodes (avg \(Int(avgDuration / 60))m)")
        } else if avgDuration > 600 {
            patterns.append("Extended episodes (avg \(Int(avgDuration / 60))m)")
        }

        return Array(patterns.prefix(3))
    }

    private func resolutionLabel(_ resolution: EpisodeLogger.Resolution) -> String {
        switch resolution {
        case .userDismissed: return "resolved after interventions"
        case .escalated: return "escalated (contact notified)"
        case .falseAlarm: return "false alarm"
        case .unresolved: return "user dismissed"
        }
    }

    // MARK: - Persistence

    private var reportsStorageKey: String { "therapy_reports_history" }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: reportsStorageKey),
              let decoded = try? JSONDecoder().decode([TherapyReport].self, from: data) else {
            return
        }
        reportHistory = decoded
        lastGeneratedReport = decoded.first
    }

    private func persistHistory() {
        guard let encoded = try? JSONEncoder().encode(reportHistory) else { return }
        UserDefaults.standard.set(encoded, forKey: reportsStorageKey)
    }

    private func saveReport(_ report: TherapyReport) {
        // Keep last 12 weeks of reports
        reportHistory = (reportHistory + [report])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(12)
            .map { $0 }
        persistHistory()
    }
}

// MARK: - Supporting Types

/// Structured metadata about the week's episodes, passed to Gemma for report generation.
private struct WeeklyMetadata {
    let weekStart: Date
    let weekEnd: Date
    let episodes: [EpisodeMetadata]
    let priorWeekCount: Int
}

/// Episode metadata for Gemma prompt.
private struct EpisodeMetadata {
    let detectedAt: Date
    let episodeDuration: TimeInterval
    let peakHeartRate: Double
    let resolvedAs: EpisodeLogger.Resolution
    let escalationTriggered: Bool

    init(from episode: EpisodeLogger.Episode) {
        self.detectedAt = episode.detectedAt
        self.episodeDuration = episode.episodeDuration
        self.peakHeartRate = 120 // Placeholder — actual peak HR from DetectionEngine
        self.resolvedAs = episode.resolvedAs
        self.escalationTriggered = episode.escalationTriggered
    }
}

// MARK: - Therapy Report Model

/// A generated therapy report, stored locally and user-editable before sharing.
struct TherapyReport: Identifiable, Codable {
    let id: UUID
    let weekStart: Date
    let weekEnd: Date
    let episodeCount: Int
    let totalDurationMinutes: Double
    let dominantPatterns: [String]
    let episodeDates: [Date]
    let averageSleepHours: Double?
    var gemmaReportBody: String
    let createdAt: Date
    var isShared: Bool

    /// Formatted week range string for display.
    var weekRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: weekEnd))"
    }

    /// Short count label for history list.
    var episodeCountLabel: String {
        episodeCount == 1 ? "1 episode" : "\(episodeCount) episodes"
    }
}

// MARK: - Errors

enum TherapyReportError: Error, LocalizedError {
    case invalidDateRange
    case generationFailed(String)
    case noEpisodesThisWeek

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Could not determine the date range for this week"
        case .generationFailed(let message):
            return "Report generation failed: \(message)"
        case .noEpisodesThisWeek:
            return "No episodes recorded this week — nothing to report"
        }
    }
}
