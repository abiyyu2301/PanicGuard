import Foundation
import SQLite

/// Logs panic guard episodes and daily companion data locally using SQLite.
/// All data stays on-device per PRD Section 4.5.
final class EpisodeLogger {

    // MARK: - Resolution Enum

    enum Resolution: String, CaseIterable {
        case userDismissed = "user_dismissed"
        case escalated = "escalated"
        case falseAlarm = "false_alarm"
        case unresolved = "unresolved"
    }

    // MARK: - Episode Struct

    struct Episode {
        let id: UUID
        let detectedAt: Date
        let confidence: Double
        let resolvedAs: Resolution
        let escalationTriggered: Bool
        let contactNotified: Bool
        let episodeDuration: TimeInterval
    }

    // MARK: - JournalEntry Struct

    struct JournalEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let content: String
        let emotionalTags: [String]
        let linkedEpisodeId: UUID?
        let gemmaSummary: String?
        let gemmaInsights: [String]
    }

    // MARK: - TriggerCorrelation Struct

    struct TriggerCorrelation: Identifiable {
        let id: UUID
        let patternType: PatternType
        let patternDescription: String
        let confidence: Double
        let episodeCount: Int
        let supportingDetails: String
        let lastUpdated: Date
        let isActive: Bool

        enum PatternType: String, CaseIterable {
            case timeOfDay = "time_of_day"
            case calendarEvent = "calendar_event"
            case sleepDebt = "sleep_debt"
            case journalTheme = "journal_theme"
            case exerciseContext = "exercise_context"
            case none = "none"
        }
    }

    // MARK: - NudgeLog Struct

    struct NudgeLog: Identifiable {
        let id: UUID
        let scheduledAt: Date
        let deliveredAt: Date?
        let eventDescription: String
        let triggerCorrelationId: UUID?
        let accepted: Bool?
        let gemmaPrompt: String
    }

    // MARK: - TherapyReport Struct

    struct TherapyReport: Identifiable {
        let id: UUID
        let weekStart: Date
        let weekEnd: Date
        let episodeCount: Int
        let totalDurationMinutes: Double
        let dominantPatterns: [String]
        let episodeDates: [Date]
        let averageSleepHours: Double?
        let gemmaReportBody: String
        let createdAt: Date
        let isShared: Bool
    }

    // MARK: - Table Definitions

    private let episodes = Table("episodes")
    private let journalEntries = Table("journal_entries")
    private let triggerCorrelations = Table("trigger_correlations")
    private let nudgeLog = Table("nudge_log")
    private let therapyReports = Table("therapy_reports")

    // Episodes columns
    private let id = Expression<String>("id")
    private let detectedAt = Expression<Double>("detected_at")
    private let confidence = Expression<Double>("confidence")
    private let resolvedAs = Expression<String>("resolved_as")
    private let escalationTriggered = Expression<Bool>("escalation_triggered")
    private let contactNotified = Expression<Bool>("contact_notified")
    private let episodeDuration = Expression<Double>("episode_duration")

    // Journal entries columns
    private let jeTimestamp = Expression<Double>("timestamp")
    private let jeContent = Expression<String>("content")
    private let jeEmotionalTags = Expression<String>("emotional_tags")
    private let jeLinkedEpisodeId = Expression<String?>("linked_episode_id")
    private let jeGemmaSummary = Expression<String?>("gemma_summary")
    private let jeGemmaInsights = Expression<String>("gemma_insights")

    // Trigger correlations columns
    private let tcPatternType = Expression<String>("pattern_type")
    private let tcPatternDescription = Expression<String>("pattern_description")
    private let tcConfidence = Expression<Double>("confidence")
    private let tcEpisodeCount = Expression<Int>("episode_count")
    private let tcSupportingDetails = Expression<String>("supporting_details")
    private let tcLastUpdated = Expression<Double>("last_updated")
    private let tcIsActive = Expression<Bool>("is_active")

    // Nudge log columns
    private let nlScheduledAt = Expression<Double>("scheduled_at")
    private let nlDeliveredAt = Expression<Double?>("delivered_at")
    private let nlEventDescription = Expression<String>("event_description")
    private let nlTriggerCorrelationId = Expression<String?>("trigger_correlation_id")
    private let nlAccepted = Expression<Bool?>("accepted")
    private let nlGemmaPrompt = Expression<String>("gemma_prompt")

    // Therapy reports columns
    private let trWeekStart = Expression<Double>("week_start")
    private let trWeekEnd = Expression<Double>("week_end")
    private let trEpisodeCount = Expression<Int>("episode_count")
    private let trTotalDurationMinutes = Expression<Double>("total_duration_minutes")
    private let trDominantPatterns = Expression<String>("dominant_patterns")
    private let trEpisodeDates = Expression<String>("episode_dates")
    private let trAverageSleepHours = Expression<Double?>("average_sleep_hours")
    private let trGemmaReportBody = Expression<String>("gemma_report_body")
    private let trCreatedAt = Expression<Double>("created_at")
    private let trIsShared = Expression<Bool>("is_shared")

    // MARK: - Database Connection

    private var db: Connection? {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let dbPath = documentsPath.appendingPathComponent("panic_guard.sqlite3").path
        return try? Connection(dbPath)
    }

    // MARK: - Initialization

    init() {
        createTablesIfNeeded()
    }

    private func createTablesIfNeeded() {
        guard let db = db else { return }

        // Episodes table
        try? db.run(episodes.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(detectedAt)
            t.column(confidence)
            t.column(resolvedAs)
            t.column(escalationTriggered)
            t.column(contactNotified)
            t.column(episodeDuration)
        })

        // Journal entries table
        try? db.run(journalEntries.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(jeTimestamp)
            t.column(jeContent)
            t.column(jeEmotionalTags)
            t.column(jeLinkedEpisodeId)
            t.column(jeGemmaSummary)
            t.column(jeGemmaInsights)
        })

        // Trigger correlations table
        try? db.run(triggerCorrelations.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(tcPatternType)
            t.column(tcPatternDescription)
            t.column(tcConfidence)
            t.column(tcEpisodeCount)
            t.column(tcSupportingDetails)
            t.column(tcLastUpdated)
            t.column(tcIsActive)
        })

        // Nudge log table
        try? db.run(nudgeLog.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(nlScheduledAt)
            t.column(nlDeliveredAt)
            t.column(nlEventDescription)
            t.column(nlTriggerCorrelationId)
            t.column(nlAccepted)
            t.column(nlGemmaPrompt)
        })

        // Therapy reports table
        try? db.run(therapyReports.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(trWeekStart)
            t.column(trWeekEnd)
            t.column(trEpisodeCount)
            t.column(trTotalDurationMinutes)
            t.column(trDominantPatterns)
            t.column(trEpisodeDates)
            t.column(trAverageSleepHours)
            t.column(trGemmaReportBody)
            t.column(trCreatedAt)
            t.column(trIsShared)
        })
    }

    // MARK: - Episode CRUD

    func insert(_ episode: Episode) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let insert = episodes.insert(
            id <- episode.id.uuidString,
            detectedAt <- episode.detectedAt.timeIntervalSince1970,
            confidence <- episode.confidence,
            resolvedAs <- episode.resolvedAs.rawValue,
            escalationTriggered <- episode.escalationTriggered,
            contactNotified <- episode.contactNotified,
            episodeDuration <- episode.episodeDuration
        )
        try db.run(insert)
    }

    func queryAllEpisodes() throws -> [Episode] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = episodes.order(detectedAt.desc)
        return try db.prepare(query).map { row in
            Episode(
                id: UUID(uuidString: row[id]) ?? UUID(),
                detectedAt: Date(timeIntervalSince1970: row[detectedAt]),
                confidence: row[confidence],
                resolvedAs: Resolution(rawValue: row[resolvedAs]) ?? .unresolved,
                escalationTriggered: row[escalationTriggered],
                contactNotified: row[contactNotified],
                episodeDuration: row[episodeDuration]
            )
        }
    }

    func queryEpisodes(from startDate: Date, to endDate: Date) throws -> [Episode] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = episodes
            .filter(detectedAt >= startDate.timeIntervalSince1970 && detectedAt <= endDate.timeIntervalSince1970)
            .order(detectedAt.desc)
        return try db.prepare(query).map { row in
            Episode(
                id: UUID(uuidString: row[id]) ?? UUID(),
                detectedAt: Date(timeIntervalSince1970: row[detectedAt]),
                confidence: row[confidence],
                resolvedAs: Resolution(rawValue: row[resolvedAs]) ?? .unresolved,
                escalationTriggered: row[escalationTriggered],
                contactNotified: row[contactNotified],
                episodeDuration: row[episodeDuration]
            )
        }
    }

    /// Returns episodes from the last 24 hours.
    func queryRecentEpisodes(hours: Int = 24) throws -> [Episode] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return try queryEpisodes(from: cutoff, to: Date())
    }

    // MARK: - JournalEntry CRUD

    func insert(_ entry: JournalEntry) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let insert = journalEntries.insert(
            id <- entry.id.uuidString,
            jeTimestamp <- entry.timestamp.timeIntervalSince1970,
            jeContent <- entry.content,
            jeEmotionalTags <- entry.emotionalTags.joined(separator: ","),
            jeLinkedEpisodeId <- entry.linkedEpisodeId?.uuidString,
            jeGemmaSummary <- entry.gemmaSummary,
            jeGemmaInsights <- entry.gemmaInsights.joined(separator: ",")
        )
        try db.run(insert)
    }

    func queryAllJournalEntries() throws -> [JournalEntry] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = journalEntries.order(jeTimestamp.desc)
        return try db.prepare(query).map { row in
            JournalEntry(
                id: UUID(uuidString: row[id]) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: row[jeTimestamp]),
                content: row[jeContent],
                emotionalTags: row[jeEmotionalTags].split(separator: ",").map(String.init),
                linkedEpisodeId: row[jeLinkedEpisodeId].flatMap { UUID(uuidString: $0) },
                gemmaSummary: row[jeGemmaSummary],
                gemmaInsights: row[jeGemmaInsights].split(separator: ",").map(String.init)
            )
        }
    }

    func queryJournalEntries(from startDate: Date, to endDate: Date) throws -> [JournalEntry] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = journalEntries
            .filter(jeTimestamp >= startDate.timeIntervalSince1970 && jeTimestamp <= endDate.timeIntervalSince1970)
            .order(jeTimestamp.desc)
        return try db.prepare(query).map { row in
            JournalEntry(
                id: UUID(uuidString: row[id]) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: row[jeTimestamp]),
                content: row[jeContent],
                emotionalTags: row[jeEmotionalTags].split(separator: ",").map(String.init),
                linkedEpisodeId: row[jeLinkedEpisodeId].flatMap { UUID(uuidString: $0) },
                gemmaSummary: row[jeGemmaSummary],
                gemmaInsights: row[jeGemmaInsights].split(separator: ",").map(String.init)
            )
        }
    }

    // MARK: - TriggerCorrelation CRUD

    func insert(_ correlation: TriggerCorrelation) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let insert = triggerCorrelations.insert(
            id <- correlation.id.uuidString,
            tcPatternType <- correlation.patternType.rawValue,
            tcPatternDescription <- correlation.patternDescription,
            tcConfidence <- correlation.confidence,
            tcEpisodeCount <- correlation.episodeCount,
            tcSupportingDetails <- correlation.supportingDetails,
            tcLastUpdated <- correlation.lastUpdated.timeIntervalSince1970,
            tcIsActive <- correlation.isActive
        )
        try db.run(insert)
    }

    func queryAllTriggerCorrelations() throws -> [TriggerCorrelation] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = triggerCorrelations.order(tcLastUpdated.desc)
        return try db.prepare(query).map { row in
            TriggerCorrelation(
                id: UUID(uuidString: row[id]) ?? UUID(),
                patternType: TriggerCorrelation.PatternType(rawValue: row[tcPatternType]) ?? .none,
                patternDescription: row[tcPatternDescription],
                confidence: row[tcConfidence],
                episodeCount: row[tcEpisodeCount],
                supportingDetails: row[tcSupportingDetails],
                lastUpdated: Date(timeIntervalSince1970: row[tcLastUpdated]),
                isActive: row[tcIsActive]
            )
        }
    }

    func queryActiveTriggerCorrelations() throws -> [TriggerCorrelation] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = triggerCorrelations.filter(tcIsActive == true).order(tcConfidence.desc)
        return try db.prepare(query).map { row in
            TriggerCorrelation(
                id: UUID(uuidString: row[id]) ?? UUID(),
                patternType: TriggerCorrelation.PatternType(rawValue: row[tcPatternType]) ?? .none,
                patternDescription: row[tcPatternDescription],
                confidence: row[tcConfidence],
                episodeCount: row[tcEpisodeCount],
                supportingDetails: row[tcSupportingDetails],
                lastUpdated: Date(timeIntervalSince1970: row[tcLastUpdated]),
                isActive: row[tcIsActive]
            )
        }
    }

    func updateTriggerCorrelation(_ correlation: TriggerCorrelation) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let target = triggerCorrelations.filter(id == correlation.id.uuidString)
        try db.run(target.update(
            tcPatternType <- correlation.patternType.rawValue,
            tcPatternDescription <- correlation.patternDescription,
            tcConfidence <- correlation.confidence,
            tcEpisodeCount <- correlation.episodeCount,
            tcSupportingDetails <- correlation.supportingDetails,
            tcLastUpdated <- correlation.lastUpdated.timeIntervalSince1970,
            tcIsActive <- correlation.isActive
        ))
    }

    // MARK: - NudgeLog CRUD

    func insert(_ nudge: NudgeLog) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let insert = nudgeLog.insert(
            id <- nudge.id.uuidString,
            nlScheduledAt <- nudge.scheduledAt.timeIntervalSince1970,
            nlDeliveredAt <- nudge.deliveredAt?.timeIntervalSince1970,
            nlEventDescription <- nudge.eventDescription,
            nlTriggerCorrelationId <- nudge.triggerCorrelationId?.uuidString,
            nlAccepted <- nudge.accepted,
            nlGemmaPrompt <- nudge.gemmaPrompt
        )
        try db.run(insert)
    }

    func queryAllNudgeLogs() throws -> [NudgeLog] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = nudgeLog.order(nlScheduledAt.desc)
        return try db.prepare(query).map { row in
            NudgeLog(
                id: UUID(uuidString: row[id]) ?? UUID(),
                scheduledAt: Date(timeIntervalSince1970: row[nlScheduledAt]),
                deliveredAt: row[nlDeliveredAt].map { Date(timeIntervalSince1970: $0) },
                eventDescription: row[nlEventDescription],
                triggerCorrelationId: row[nlTriggerCorrelationId].flatMap { UUID(uuidString: $0) },
                accepted: row[nlAccepted],
                gemmaPrompt: row[nlGemmaPrompt]
            )
        }
    }

    func markNudgeDelivered(id nudgeId: UUID, accepted: Bool?) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let target = nudgeLog.filter(id == nudgeId.uuidString)
        try db.run(target.update(
            nlDeliveredAt <- Date().timeIntervalSince1970,
            nlAccepted <- accepted
        ))
    }

    // MARK: - TherapyReport CRUD

    func insert(_ report: TherapyReport) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let insert = therapyReports.insert(
            id <- report.id.uuidString,
            trWeekStart <- report.weekStart.timeIntervalSince1970,
            trWeekEnd <- report.weekEnd.timeIntervalSince1970,
            trEpisodeCount <- report.episodeCount,
            trTotalDurationMinutes <- report.totalDurationMinutes,
            trDominantPatterns <- report.dominantPatterns.joined(separator: "|||"),
            trEpisodeDates <- report.episodeDates.map { $0.timeIntervalSince1970 }.joined(separator: ","),
            trAverageSleepHours <- report.averageSleepHours,
            trGemmaReportBody <- report.gemmaReportBody,
            trCreatedAt <- report.createdAt.timeIntervalSince1970,
            trIsShared <- report.isShared
        )
        try db.run(insert)
    }

    func queryAllTherapyReports() throws -> [TherapyReport] {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let query = therapyReports.order(trWeekStart.desc)
        return try db.prepare(query).map { row in
            TherapyReport(
                id: UUID(uuidString: row[id]) ?? UUID(),
                weekStart: Date(timeIntervalSince1970: row[trWeekStart]),
                weekEnd: Date(timeIntervalSince1970: row[trWeekEnd]),
                episodeCount: row[trEpisodeCount],
                totalDurationMinutes: row[trTotalDurationMinutes],
                dominantPatterns: row[trDominantPatterns].split(separator: "|||").map(String.init),
                episodeDates: row[trEpisodeDates].split(separator: ",").compactMap { Double($0) }.map { Date(timeIntervalSince1970: $0) },
                averageSleepHours: row[trAverageSleepHours],
                gemmaReportBody: row[trGemmaReportBody],
                createdAt: Date(timeIntervalSince1970: row[trCreatedAt]),
                isShared: row[trIsShared]
            )
        }
    }

    func markTherapyReportShared(id reportId: UUID) throws {
        guard let db = db else {
            throw EpisodeLoggerError.databaseUnavailable
        }
        let target = therapyReports.filter(id == reportId.uuidString)
        try db.run(target.update(trIsShared <- true))
    }

    // MARK: - Episode History for Gemma

    /// Returns the count of episodes in the last 24 hours and hours since the most recent episode.
    func getRecentEpisodeContext() -> (count: Int, hoursSinceLast: Float?) {
        do {
            let recent = try queryRecentEpisodes(hours: 24)
            guard let lastEpisode = recent.first else {
                return (0, nil)
            }
            let hoursSince = Float(Date().timeIntervalSince(lastEpisode.detectedAt) / 3600)
            return (recent.count, hoursSince)
        } catch {
            print("[EpisodeLogger] Failed to query recent episodes: \(error)")
            return (0, nil)
        }
    }
}

// MARK: - Errors

enum EpisodeLoggerError: Error, LocalizedError {
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Database connection unavailable"
        }
    }
}
