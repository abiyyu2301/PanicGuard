import Foundation

// MARK: - Panic Episode Model
struct PanicEpisode: Identifiable, Codable {

    let id: UUID
    let timestamp: Date

    // Detection metrics
    let confidenceScore: Double
    let heartRateAtDetection: Double
    let peakHeartRate: Double
    let hrvAtDetection: Double
    let rmssd: Double?

    // Episode outcome
    let resolution: EpisodeResolution
    let escalated: Bool
    let escalatedContactName: String?

    // Duration (seconds)
    let durationSeconds: Double

    // Interventions used during this episode
    let interventionsUsed: [InterventionType]

    // Context
    let sleepHoursPrior: Double?
    let calendarEventContext: String?
    let linkedJournalEntryId: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        confidenceScore: Double,
        heartRateAtDetection: Double,
        peakHeartRate: Double,
        hrvAtDetection: Double,
        rmssd: Double? = nil,
        resolution: EpisodeResolution = .unknown,
        escalated: Bool = false,
        escalatedContactName: String? = nil,
        durationSeconds: Double = 0,
        interventionsUsed: [InterventionType] = [],
        sleepHoursPrior: Double? = nil,
        calendarEventContext: String? = nil,
        linkedJournalEntryId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.confidenceScore = confidenceScore
        self.heartRateAtDetection = heartRateAtDetection
        self.peakHeartRate = peakHeartRate
        self.hrvAtDetection = hrvAtDetection
        self.rmssd = rmssd
        self.resolution = resolution
        self.escalated = escalated
        self.escalatedContactName = escalatedContactName
        self.durationSeconds = durationSeconds
        self.interventionsUsed = interventionsUsed
        self.sleepHoursPrior = sleepHoursPrior
        self.calendarEventContext = calendarEventContext
        self.linkedJournalEntryId = linkedJournalEntryId
    }
}

// MARK: - Duration Helpers

extension PanicEpisode {
    /// Duration formatted as "Xm Ys", e.g. "6m 12s".
    var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Duration in minutes (fractional).
    var durationMinutes: Double {
        durationSeconds / 60.0
    }
}

enum EpisodeResolution: String, Codable {
    case userDismissed = "resolved:user_dismissed"
    case gemmaResolved = "resolved:gemma_resolved"
    case escalated = "escalated:resolved"
    case escalatedUnresolved = "escalated:unresolved"
    case escalatedCancelled = "escalated:cancelled"
    case unknown = "unknown"
}

// MARK: - Detection State
enum DetectionState: Equatable {
    case idle
    case monitoring
    case signalElevated(confidence: Double)
    case panicDetected(confidence: Double)
    case interventionActive(type: InterventionType)
    case escalationActive
}

// MARK: - Intervention Type
enum InterventionType: String, Codable {
    case breathingExercise = "breathing_exercise"
    case groundingPrompt = "grounding_prompt"
    case hapticRhythm = "haptic_rhythm"
    case checkIn = "check_in"
    case escalate = "escalate"
    case dismiss = "dismiss"
}

// MARK: - Emergency Contact
struct EmergencyContact: Codable {
    var name: String
    var phone: String
    var relationship: String

    static var placeholder: EmergencyContact {
        EmergencyContact(name: "", phone: "", relationship: "")
    }
}
