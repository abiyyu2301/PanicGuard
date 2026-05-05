import Foundation

// MARK: - TherapyReport Store
/// Lightweight SQLite-backed store for therapy reports.
/// All data stays on-device per PRD Section 4.5.
final class TherapyReportStore {

    private let reports = Table("therapy_reports")

    private let id                = Expression<String>("id")
    private let weekStart        = Expression<Double>("week_start")
    private let weekEnd          = Expression<Double>("week_end")
    private let episodeCount      = Expression<Int>("episode_count")
    private let totalDuration     = Expression<Double>("total_duration_minutes")
    private let dominantPatterns  = Expression<String>("dominant_patterns") // JSON
    private let episodeDates      = Expression<String>("episode_dates")      // JSON
    private let averageSleepHours = Expression<Double?>("average_sleep_hours")
    private let gemmaReportBody   = Expression<String>("gemma_report_body")
    private let createdAt        = Expression<Double>("created_at")
    private let isShared          = Expression<Bool>("is_shared")

    private var db: Connection? {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let dbPath = documentsPath.appendingPathComponent("panic_guard.sqlite3").path
        return try? Connection(dbPath)
    }

    init() { createTableIfNeeded() }

    private func createTableIfNeeded() {
        guard let db = db else { return }
        try? db.run(reports.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(weekStart)
            t.column(weekEnd)
            t.column(episodeCount)
            t.column(totalDuration)
            t.column(dominantPatterns)
            t.column(episodeDates)
            t.column(averageSleepHours)
            t.column(gemmaReportBody)
            t.column(createdAt)
            t.column(isShared)
        })
    }

    func insert(_ report: TherapyReport) throws {
        guard let db = db else { throw TherapyReportStoreError.databaseUnavailable }

        let patternsJSON = (try? JSONEncoder().encode(report.dominantPatterns))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let datesJSON = (try? JSONEncoder().encode(report.episodeDates))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        try db.run(reports.insert(
            id <- report.id.uuidString,
            weekStart <- report.weekStart.timeIntervalSince1970,
            weekEnd <- report.weekEnd.timeIntervalSince1970,
            episodeCount <- report.episodeCount,
            totalDuration <- report.totalDurationMinutes,
            dominantPatterns <- patternsJSON,
            episodeDates <- datesJSON,
            averageSleepHours <- report.averageSleepHours,
            gemmaReportBody <- report.gemmaReportBody,
            createdAt <- report.createdAt.timeIntervalSince1970,
            isShared <- report.isShared
        ))
    }

    func queryAll() throws -> [TherapyReport] {
        guard let db = db else { throw TherapyReportStoreError.databaseUnavailable }
        let query = reports.order(createdAt.desc)
        return try db.prepare(query).map { row in
            let patterns: [String] = {
                guard let data = row[dominantPatterns].data(using: .utf8) else { return [] }
                return (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }()
            let dates: [Date] = {
                guard let data = row[episodeDates].data(using: .utf8) else { return [] }
                return (try? JSONDecoder().decode([Date].self, from: data)) ?? []
            }()
            return TherapyReport(
                id: UUID(uuidString: row[id]) ?? UUID(),
                weekStart: Date(timeIntervalSince1970: row[weekStart]),
                weekEnd: Date(timeIntervalSince1970: row[weekEnd]),
                episodeCount: row[episodeCount],
                totalDurationMinutes: row[totalDuration],
                dominantPatterns: patterns,
                episodeDates: dates,
                averageSleepHours: row[averageSleepHours],
                gemmaReportBody: row[gemmaReportBody],
                createdAt: Date(timeIntervalSince1970: row[createdAt]),
                isShared: row[isShared]
            )
        }
    }

    func update(_ report: TherapyReport) throws {
        guard let db = db else { throw TherapyReportStoreError.databaseUnavailable }
        let item = reports.filter(id == report.id.uuidString)
        try db.run(item.update(isShared <- report.isShared))
    }
}

enum TherapyReportStoreError: Error, LocalizedError {
    case databaseUnavailable
    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: return "Database connection unavailable"
        }
    }
}
