import Foundation
import CoreLocation

// MARK: - Escalation Service
/// Handles escalation of panic episodes to emergency contacts via Cloudflare Worker → Twilio SMS.
/// Location is acquired at escalation time (deferred) per PRD Section 12.
/// Supports simulation/demo mode for development.
final class EscalationService: ObservableObject {
    static let shared = EscalationService()

    // MARK: - Published State
    @Published var isEscalationActive: Bool = false
    @Published var escalationMessageSent: Bool = false

    // MARK: - Private State
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var activeEscalations: [UUID: EscalationRecord] = [:]

    /// Demo mode flag - when true, simulates escalation without network calls
    var isDemoMode: Bool = false

    // MARK: - Cloudflare Worker Configuration
    private let workerBaseURL = "https://panicguard-escalation.your-account.workers.dev"

    // MARK: - Errors
    enum EscalationError: Error, LocalizedError {
        case locationUnavailable
        case networkError(String)
        case workerError(String)
        case invalidResponse
        case cancelled

        var errorDescription: String? {
            switch self {
            case .locationUnavailable:
                return "Unable to determine current location"
            case .networkError(let message):
                return "Network error: \(message)"
            case .workerError(let message):
                return "Worker error: \(message)"
            case .invalidResponse:
                return "Invalid response from server"
            case .cancelled:
                return "Escalation was cancelled"
            }
        }
    }

    // MARK: - Escalation Record
    private struct EscalationRecord {
        let episodeId: UUID
        let contact: EmergencyContact
        let messageId: String
        let timestamp: Date
        var isCancelled: Bool
    }

    // MARK: - Initialization
    private init() {
        // NOTE: locationManager.requestWhenInUseAuthorization() is NOT called here.
        // Per APP_AUDIT.md C10, location auth is deferred until escalation trigger.
        locationManager.delegate = LocationDelegate.shared
    }

    // MARK: - Request Location Authorization (Deferred Until Escalation)
    /// Requests location authorization only when escalation is triggered.
    /// This is called at escalation time, not at app init (per C10).
    private func ensureLocationAuthorization() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Escalate
    /// Sends an escalation SMS to the emergency contact via Cloudflare Worker → Twilio.
    /// Location is acquired at escalation time (deferred).
    /// - Parameters:
    ///   - contact: The emergency contact to notify
    ///   - userFirstName: User's first name for personalization
    ///   - episodeId: Unique identifier for this panic episode
    /// - Returns: true if escalation was sent successfully, false otherwise
    @MainActor
    func escalate(
        contact: EmergencyContact,
        userFirstName: String,
        episodeId: UUID
    ) async -> Bool {
        isEscalationActive = true
        escalationMessageSent = false

        // Request location authorization only now (deferred until escalation, per C10)
        ensureLocationAuthorization()

        // Acquire location at escalation time (deferred until needed)
        let address = await getCurrentAddress() ?? "Location unavailable"

        // Build payload matching Cloudflare Worker interface
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let messageId = episodeId.uuidString

        let payload = EscalationPayload(
            contactName: contact.name,
            contactPhone: contact.phone,
            userFirstName: userFirstName,
            timestamp: timestamp,
            locationAddress: address,
            messageId: messageId
        )

        // Track this escalation
        let record = EscalationRecord(
            episodeId: episodeId,
            contact: contact,
            messageId: messageId,
            timestamp: Date(),
            isCancelled: false
        )
        activeEscalations[episodeId] = record

        // Send via worker or simulate in demo mode
        let success: Bool
        if isDemoMode {
            success = await simulateEscalation(payload: payload, episodeId: episodeId)
        } else {
            success = await sendToWorker(payload: payload, episodeId: episodeId)
        }

        escalationMessageSent = success

        if !success {
            isEscalationActive = false
        }

        return success
    }

    // MARK: - Cancel Escalation
    /// Attempts to cancel an in-progress escalation.
    /// Note: Twilio SMS cannot be recalled once sent. This marks the escalation as
    /// cancelled locally and prevents further retry attempts.
    /// - Parameter episodeId: The episode ID of the escalation to cancel
    /// - Returns: true if the escalation was found and marked as cancelled
    @discardableResult
    func cancelEscalation(episodeId: UUID) -> Bool {
        guard var record = activeEscalations[episodeId] else {
            print("No active escalation found for episode: \(episodeId)")
            return false
        }

        record.isCancelled = true
        activeEscalations[episodeId] = record

        // If already sent, we cannot recall the SMS
        // but we can prevent any retry logic
        if escalationMessageSent {
            print("Escalation already sent for episode \(episodeId). SMS cannot be recalled.")
        }

        // Reset state if this is the currently active escalation
        if isEscalationActive && record.episodeId == episodeId {
            isEscalationActive = false
            escalationMessageSent = false
        }

        return true
    }

    // MARK: - Worker Communication
    /// Sends escalation payload to Cloudflare Worker which forwards to Twilio.
    private func sendToWorker(payload: EscalationPayload, episodeId: UUID) async -> Bool {
        guard let url = URL(string: "\(workerBaseURL)/escalate") else {
            print("Invalid worker URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                return false
            }

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                if let result = try? decoder.decode(WorkerResponse.self, from: data) {
                    print("Escalation sent. Worker response: \(result)")
                    return true
                }
                // Even if we can't decode response, 200 means success
                return true
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Worker error (\(httpResponse.statusCode)): \(errorMessage)")
                return false
            }
        } catch {
            print("Network error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Demo/Simulation Mode
    /// Simulates escalation without making actual network calls.
    /// Used during demo mode when isDemoMode is true.
    private func simulateEscalation(payload: EscalationPayload, episodeId: UUID) async -> Bool {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Log the simulated escalation
        print("""
        [DEMO] Escalation simulated:
        - To: \(payload.contactName) (\(payload.contactPhone))
        - From: \(payload.userFirstName)
        - Time: \(payload.timestamp)
        - Location: \(payload.locationAddress)
        - MessageId: \(payload.messageId)
        """)

        // Simulate success
        return true
    }

    // MARK: - Location (Deferred until Escalation)
    /// Acquires the current location and reverse geocodes it to a readable address.
    /// This is called at escalation time, not when the app starts.
    private func getCurrentAddress() async -> String? {
        return await withCheckedContinuation { continuation in
            LocationDelegate.shared.reverseGeocodeLocation { address in
                continuation.resume(returning: address)
            }
        }
    }

    /// Requests a single location update.
    func requestLocation() {
        locationManager.requestLocation()
    }
}

// MARK: - Location Delegate
/// Shared location delegate to handle CLLocationManagerDelegate callbacks.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    static let shared = LocationDelegate()

    private var geocodeContinuation: ((String?) -> Void)?

    private override init() {
        super.init()
    }

    func reverseGeocodeLocation(completion: @escaping (String?) -> Void) {
        self.geocodeContinuation = completion

        let locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            geocodeContinuation?(nil)
            return
        }

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let placemark = placemarks?.first {
                let address = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                self?.geocodeContinuation?(address)
            } else {
                self?.geocodeContinuation?(nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        geocodeContinuation?(nil)
    }
}

// MARK: - Escalation Payload
/// Payload sent to Cloudflare Worker, matching TypeScript interface exactly.
struct EscalationPayload: Codable {
    let contactName: String
    let contactPhone: String
    let userFirstName: String
    let timestamp: String       // ISO 8601
    let locationAddress: String  // Reverse-geocoded readable address
    let messageId: String        // For deduplication / cancellation
}

// MARK: - Worker Response
/// Response from Cloudflare Worker.
struct WorkerResponse: Codable {
    let status: String
    let messageId: String
    let twilioSid: String?
}
