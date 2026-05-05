import Foundation
import EventKit

// MARK: - Calendar Trigger
/// A calendar event identified as a potential panic-trigger scenario.
struct CalendarTrigger: Identifiable, Equatable {
    let id: UUID
    /// The event title with the [PG-xxx] tag stripped away.
    let title: String
    /// When the event starts.
    let date: Date
    /// PanicGuard category inferred from the event's tag.
    let category: TriggerCategory

    init(id: UUID = UUID(), title: String, date: Date, category: TriggerCategory) {
        self.id = id
        self.title = title
        self.date = date
        self.category = category
    }
}

// MARK: - Trigger Category
enum TriggerCategory: String, Codable, CaseIterable {
    case work     = "work"
    case social   = "social"
    case therapy  = "therapy"
    case exercise = "exercise"
    case travel   = "travel"

    /// All supported PanicGuard tag prefixes (lowercase, no brackets).
    static let tagPrefixes: [String] = [
        "pg-work", "pg-social", "pg-therapy", "pg-exercise", "pg-travel"
    ]

    /// Derive a category from a tag string (e.g. "pg-work" → .work).
    static func from(tag: String) -> TriggerCategory? {
        switch tag.lowercased() {
        case "pg-work":     return .work
        case "pg-social":   return .social
        case "pg-therapy":  return .therapy
        case "pg-exercise": return .exercise
        case "pg-travel":   return .travel
        default:            return nil
        }
    }
}

// MARK: - Calendar Integration Service
/// Reads EventKit events tagged with PanicGuard trigger prefixes.
/// Manual tagging approach (option 2 per audit C8) — user adds [PG-xxx] to event titles.
final class CalendarIntegrationService: ObservableObject {
    static let shared = CalendarIntegrationService()

    private let eventStore = EKEventStore()

    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        updateAuthorizationState()
    }

    // MARK: - Authorization

    /// Requests full-calendar read access. Returns true if granted.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            return granted
        } catch {
            print("CalendarIntegrationService: authorization failed — \(error.localizedDescription)")
            return false
        }
    }

    /// Returns the current authorization status without prompting.
    func checkAuthorization() -> EKAuthorizationStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        isAuthorized = status == .fullAccess
        return status
    }

    private func updateAuthorizationState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        isAuthorized = status == .fullAccess
    }

    // MARK: - Fetch Upcoming Triggers

    /// Fetches calendar events tagged with [PG-xxx] categories within the next `daysAhead` days.
    /// - Parameter daysAhead: Number of days to look ahead from today (default: 7).
    /// - Returns: An array of `CalendarTrigger` sorted by event start date.
    func fetchUpcomingTriggers(daysAhead: Int = 7) async -> [CalendarTrigger] {
        guard checkAuthorization() == .fullAccess else {
            print("CalendarIntegrationService: not authorized to read events")
            return []
        }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil   // nil = all calendars
        )

        let events = eventStore.events(matching: predicate)
        let triggers = parseTriggers(from: events)

        return triggers.sorted { $0.date < $1.date }
    }

    /// Overload that returns triggers from a specific start date (inclusive) to an end date (inclusive).
    func fetchTriggers(from startDate: Date, to endDate: Date) async -> [CalendarTrigger] {
        guard checkAuthorization() == .fullAccess else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
        return parseTriggers(from: events).sorted { $0.date < $1.date }
    }

    // MARK: - Parse Triggers

    /// Extracts PanicGuard trigger tags from event titles and returns CalendarTrigger objects.
    private func parseTriggers(from events: [EKEvent]) -> [CalendarTrigger] {
        var triggers: [CalendarTrigger] = []

        for event in events {
            guard let title = event.title, !title.isEmpty else { continue }

            if let (category, emojiFreeTitle) = extractCategoryAndTitle(from: title) {
                let trigger = CalendarTrigger(
                    title: emojiFreeTitle.trimmingCharacters(in: .whitespaces),
                    date: event.startDate,
                    category: category
                )
                triggers.append(trigger)
            }
        }

        return triggers
    }

    /// Parses a PanicGuard tag from an event title.
    /// Returns `(category, titleWithTagRemoved)` if a valid [PG-xxx] tag is found, otherwise nil.
    ///
    /// Supports formats:
    ///   - `[PG-work] Quarterly Review`
    ///   - `[pg-work] Quarterly Review`
    ///   - `[PG-WORK] Quarterly Review`
    private func extractCategoryAndTitle(
        from title: String
    ) -> (TriggerCategory, String)? {
        // Pattern: whitespace* [ PG-workspace ] whitespace* remainder
        // Case-insensitive on the tag portion.
        let pattern = #"^\s*\[(PG-[a-zA-Z]+)\]\s*(.*)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                  in: title,
                  options: [],
                  range: NSRange(title.startIndex..., in: title)
              ) else {
            return nil
        }

        // The tag is in the first capture group.
        guard let tagRange = Range(match.range(at: 1), in: title) else { return nil }
        let tag = String(title[tagRange])  // e.g. "PG-work"

        guard let category = TriggerCategory.from(tag: tag) else { return nil }

        // The remainder is in the second capture group.
        let remainder: String
        if match.range(at: 2).location != NSNotFound,
           let remainderRange = Range(match.range(at: 2), in: title) {
            remainder = String(title[remainderRange])
        } else {
            remainder = ""
        }

        return (category, remainder)
    }
}

// MARK: - EKAuthorizationStatus Extension
extension EKAuthorizationStatus {
    /// True when the user has granted full read access to events.
    var isFullAccess: Bool {
        if #available(iOS 17.0, *) {
            return self == .fullAccess
        } else {
            return self == .authorized
        }
    }
}
