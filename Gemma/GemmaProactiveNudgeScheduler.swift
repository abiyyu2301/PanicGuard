import Foundation
import UserNotifications
import EventKit

// MARK: - Scheduled Nudge
/// Represents a proactive nudge that has been scheduled for delivery
/// Uses the shared TriggerCorrelation from EpisodeLogger
struct ScheduledNudge: Identifiable {
    let id: UUID
    let eventId: String            // calendar event identifier
    let eventTitle: String
    let scheduledTime: Date
    let message: String
    let triggerCorrelation: EpisodeLogger.TriggerCorrelation

    init(
        id: UUID = UUID(),
        eventId: String,
        eventTitle: String,
        scheduledTime: Date,
        message: String,
        triggerCorrelation: EpisodeLogger.TriggerCorrelation
    ) {
        self.id = id
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.scheduledTime = scheduledTime
        self.message = message
        self.triggerCorrelation = triggerCorrelation
    }
}

// MARK: - Proactive Nudge Scheduler
/// Monitors upcoming calendar events + active trigger correlations
/// to schedule proactive nudges via UserNotifications.
///
/// Logic: IF upcoming calendar event matches trigger pattern AND recent sleep < 6h
///        THEN schedule grounding nudge to fire before the event.
final class GemmaProactiveNudgeScheduler: ObservableObject {
    static let shared = GemmaProactiveNudgeScheduler()

    // MARK: - Published State
    @Published private(set) var scheduledNudges: [ScheduledNudge] = []
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastError: Error?

    // MARK: - Dependencies
    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Configuration
    private let minimumConfidenceThreshold: Double = 0.7
    private let minimumSleepHours: Float = 6.0
    private let nudgeLeadTimeMinutes: TimeInterval = 30 * 60  // 30 minutes before event
    private let monitoringIntervalSeconds: TimeInterval = 15 * 60  // refresh every 15 min

    // MARK: - Active Correlations
    /// Trigger correlations discovered by GemmaJournalCorrelator
    /// In production, inject from GemmaJournalCorrelator.shared.activeCorrelations
    @Published var activeCorrelations: [EpisodeLogger.TriggerCorrelation] = []

    // MARK: - Internal State
    private var monitoringTimer: Timer?
    private let schedulerQueue = DispatchQueue(label: "com.panicguard.nudge.scheduler", qos: .utility)

    // MARK: - Notification Category
    private let nudgeCategoryIdentifier = "PROACTIVE_NUDGE"
    private let dismissActionIdentifier = "DISMISS_NUDGE"
    private let groundActionIdentifier = "START_GROUNDING"

    private init() {}

    // MARK: - Authorization

    /// Requests calendar and notification authorization
    func requestAuthorization() async -> Bool {
        // Request notification authorization
        let notificationGranted = await requestNotificationAuthorization()

        // Request calendar authorization
        let calendarGranted = await requestCalendarAuthorization()

        return notificationGranted && calendarGranted
    }

    private func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await setupNotificationCategories()
            }
            return granted
        } catch {
            print("[GemmaProactiveNudgeScheduler] Notification auth error: \(error)")
            lastError = error
            return false
        }
    }

    private func requestCalendarAuthorization() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            return granted
        } catch {
            print("[GemmaProactiveNudgeScheduler] Calendar auth error: \(error)")
            lastError = error
            return false
        }
    }

    private func setupNotificationCategories() async {
        let dismissAction = UNNotificationAction(
            identifier: dismissActionIdentifier,
            title: "Dismiss",
            options: .destructive
        )

        let groundAction = UNNotificationAction(
            identifier: groundActionIdentifier,
            title: "Do 2-min Grounding",
            options: .foreground
        )

        let category = UNNotificationCategory(
            identifier: nudgeCategoryIdentifier,
            actions: [groundAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        notificationCenter.setNotificationCategories([category])
    }

    // MARK: - Monitoring

    /// Starts monitoring calendar events and scheduling proactive nudges
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        print("[GemmaProactiveNudgeScheduler] Started monitoring")

        // Initial scan
        Task {
            await scanAndScheduleNudges()
        }

        // Periodic refresh
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringIntervalSeconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.scanAndScheduleNudges()
            }
        }
    }

    /// Stops monitoring and cancels pending nudges
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        print("[GemmaProactiveNudgeScheduler] Stopped monitoring")

        // Cancel all pending notifications
        notificationCenter.removeAllPendingNotificationRequests()
        scheduledNudges.removeAll()
    }

    // MARK: - Core Logic

    /// Scans upcoming calendar events, checks correlations, and schedules nudges
    @MainActor
    func scanAndScheduleNudges() async {
        // Step 1: Fetch recent sleep data
        let recentSleepHours = await fetchRecentSleepHours()

        // Step 2: Only proceed if sleep is below threshold
        guard recentSleepHours < minimumSleepHours else {
            print("[GemmaProactiveNudgeScheduler] Sleep \(recentSleepHours)h >= \(minimumSleepHours)h threshold, skipping")
            return
        }

        print("[GemmaProactiveNudgeScheduler] Sleep \(recentSleepHours)h < \(minimumSleepHours)h — checking events")

        // Step 3: Fetch upcoming calendar events (next 24 hours)
        let upcomingEvents = fetchUpcomingEvents(hours: 24)

        // Step 4: Match events against trigger correlations
        for event in upcomingEvents {
            for correlation in activeCorrelations {
                if matchesCorrelation(event: event, correlation: correlation) {
                    await scheduleNudgeIfNeeded(
                        for: event,
                        correlation: correlation,
                        sleepHours: recentSleepHours
                    )
                }
            }
        }
    }

    /// Checks if a calendar event matches a trigger correlation pattern
    /// Calendar events match if patternType is .calendarEvent and the event text
    /// contains keywords from the patternDescription
    private func matchesCorrelation(event: EKEvent, correlation: EpisodeLogger.TriggerCorrelation) -> Bool {
        guard correlation.confidence >= minimumConfidenceThreshold else { return false }

        // Only calendarEvent pattern types are matched against calendar events
        guard correlation.patternType == .calendarEvent else { return false }

        let eventTitle = event.title ?? ""
        let eventNotes = event.notes ?? ""
        let eventText = "\(eventTitle) \(eventNotes)".lowercased()

        // Use patternDescription as keyword list for matching
        let keywords = correlation.patternDescription.lowercased()

        // Match against event title, notes, or calendar title
        return eventText.contains(keywords) ||
               event.calendar?.title.lowercased().contains(keywords) == true
    }

    /// Schedules a nudge for the given event if not already scheduled
    private func scheduleNudgeIfNeeded(
        for event: EKEvent,
        correlation: EpisodeLogger.TriggerCorrelation,
        sleepHours: Float
    ) async {
        // Skip if no start date
        guard let eventStart = event.startDate else { return }

        // Calculate nudge time (lead time before event)
        let nudgeTime = eventStart.addingTimeInterval(-nudgeLeadTimeMinutes)

        // Don't schedule if too close (less than 10 minutes away) or in the past
        guard nudgeTime.timeIntervalSinceNow >= 10 * 60 else {
            print("[GemmaProactiveNudgeScheduler] Event \(event.title ?? "unknown") too close, skipping")
            return
        }

        // Check if already scheduled for this event
        let alreadyScheduled = scheduledNudges.contains { $0.eventId == event.eventIdentifier }
        guard !alreadyScheduled else { return }

        // Build personalized nudge message
        let message = buildNudgeMessage(for: event, correlation: correlation, sleepHours: sleepHours)

        // Create scheduled nudge record
        let scheduledNudge = ScheduledNudge(
            eventId: event.eventIdentifier ?? UUID().uuidString,
            eventTitle: event.title ?? "Upcoming event",
            scheduledTime: nudgeTime,
            message: message,
            triggerCorrelation: correlation
        )

        // Schedule the notification
        do {
            try await scheduleNotification(for: scheduledNudge)
            scheduledNudges.append(scheduledNudge)
            print("[GemmaProactiveNudgeScheduler] Scheduled nudge for '\(event.title ?? "unknown")' at \(nudgeTime)")
        } catch {
            print("[GemmaProactiveNudgeScheduler] Failed to schedule notification: \(error)")
            lastError = error
        }
    }

    /// Builds a personalized nudge message based on user's patterns
    private func buildNudgeMessage(
        for event: EKEvent,
        correlation: EpisodeLogger.TriggerCorrelation,
        sleepHours: Float
    ) -> String {
        let eventName = event.title ?? "event"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: event.startDate ?? Date())
        let patternName = correlation.patternType.rawValue.replacingOccurrences(of: "_", with: " ")

        return "You have \(eventName) at \(timeString). Your episodes tend to cluster around \(patternName) patterns after short sleep (last night: \(String(format: "%.1f", sleepHours))h). Want to do a 2-minute grounding practice now?"
    }

    // MARK: - Calendar Access

    /// Fetches upcoming calendar events
    private func fetchUpcomingEvents(hours: Int) -> [EKEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        // Filter out all-day events and events that have already passed
        return events.filter { event in
            !event.isAllDay && event.startDate.timeIntervalSinceNow > 0
        }
    }

    // MARK: - HealthKit Integration

    /// Fetches the most recent night's total sleep duration from HealthKit
    private func fetchRecentSleepHours() async -> Float {
        let authorized = await HealthKitService.shared.requestAuthorization()
        guard authorized else {
            return 8.0  // Default assumption when not authorized
        }

        // Query last night's sleep using async wrapper
        let hours = await HealthKitService.shared.queryTotalSleep(
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        )
        return hours ?? 8.0
    }

    // MARK: - Notification Scheduling

    /// Schedules a local notification for the given nudge
    private func scheduleNotification(for nudge: ScheduledNudge) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Heads up — grounding moment"
        content.body = nudge.message
        content.sound = .default
        content.categoryIdentifier = nudgeCategoryIdentifier
        content.userInfo = [
            "nudgeId": nudge.id.uuidString,
            "eventId": nudge.eventId,
            "triggerCorrelationId": nudge.triggerCorrelation.id.uuidString
        ]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: nudge.scheduledTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: nudge.id.uuidString,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    // MARK: - Notification Handling

    /// Handles notification tap — routes to InterventionService for grounding
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo

        guard let nudgeIdString = userInfo["nudgeId"] as? String,
              let nudgeId = UUID(uuidString: nudgeIdString),
              let nudge = scheduledNudges.first(where: { $0.id == nudgeId }) else {
            return
        }

        switch response.actionIdentifier {
        case groundActionIdentifier, UNNotificationDefaultActionIdentifier:
            // User tapped "Do 2-min Grounding" or swiped to open
            print("[GemmaProactiveNudgeScheduler] User started grounding from nudge")
            triggerGroundingIntervention(for: nudge)

        case dismissActionIdentifier:
            print("[GemmaProactiveNudgeScheduler] User dismissed nudge")
            removeScheduledNudge(nudgeId)

        default:
            break
        }
    }

    /// Triggers the grounding prompt intervention
    private func triggerGroundingIntervention(for nudge: ScheduledNudge) {
        let patternName = nudge.triggerCorrelation.patternType.rawValue.replacingOccurrences(of: "_", with: " ")
        // Post notification that Gemma has decided on a proactive intervention
        NotificationCenter.default.post(
            name: .gemmaDecision,
            object: nil,
            userInfo: [
                "interventionType": InterventionType.groundingPrompt,
                "confidence": "moderate",
                "reasoning": "Proactive nudge: \(patternName) pattern + low sleep",
                "isProactive": true
            ]
        )
    }

    // MARK: - Nudge Management

    /// Removes a scheduled nudge (e.g., user dismissed or event cancelled)
    func removeScheduledNudge(_ id: UUID) {
        scheduledNudges.removeAll { $0.id == id }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        print("[GemmaProactiveNudgeScheduler] Cancelled nudge \(id)")
    }

    /// Cancels all nudges for a specific calendar event
    func cancelNudges(forEventId eventId: String) {
        let toCancel = scheduledNudges.filter { $0.eventId == eventId }
        for nudge in toCancel {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [nudge.id.uuidString])
        }
        scheduledNudges.removeAll { $0.eventId == eventId }
    }

    // MARK: - Correlation Injection

    /// Updates active trigger correlations (called by GemmaJournalCorrelator)
    func updateCorrelations(_ correlations: [EpisodeLogger.TriggerCorrelation]) {
        activeCorrelations = correlations.filter { $0.confidence >= minimumConfidenceThreshold }
        print("[GemmaProactiveNudgeScheduler] Updated \(activeCorrelations.count) active correlations")

        // Re-evaluate if we should schedule new nudges
        Task { @MainActor in
            await scanAndScheduleNudges()
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Preview/mock data for SwiftUI previews
    static func preview() -> GemmaProactiveNudgeScheduler {
        let scheduler = GemmaProactiveNudgeScheduler()
        scheduler.activeCorrelations = [
            EpisodeLogger.TriggerCorrelation(
                id: UUID(),
                patternType: .calendarEvent,
                patternDescription: "work meeting",
                confidence: 0.85,
                episodeCount: 4,
                supportingDetails: "Episodes cluster around high-stakes work events after short sleep",
                lastUpdated: Date(),
                isActive: true
            )
        ]
        return scheduler
    }
    #endif
}
