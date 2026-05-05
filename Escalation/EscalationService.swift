import Foundation
import CoreLocation

// MARK: - Escalation Service
final class EscalationService: ObservableObject {
    static let shared = EscalationService()

    @Published var isEscalationActive: Bool = false
    @Published var escalationMessageSent: Bool = false

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    private init() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Escalate
    @MainActor
    func escalate(
        contact: EmergencyContact,
        userFirstName: String,
        episodeId: UUID
    ) async -> Bool {
        isEscalationActive = true

        // Get location
        let address = await getCurrentAddress() ?? "Unknown location"

        // Build message
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let messageId = episodeId.uuidString

        // In production: Call Cloudflare Worker → Twilio
        // For MVP: Simulate
        let escalationPayload = EscalationPayload(
            contactName: contact.name,
            contactPhone: contact.phone,
            userFirstName: userFirstName,
            timestamp: timestamp,
            locationAddress: address,
            messageId: messageId
        )

        // Simulate API call
        await simulateEscalation(payload: escalationPayload)

        escalationMessageSent = true
        return true
    }

    private func simulateEscalation(payload: EscalationPayload) async {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("Escalation sent: \(payload)")
    }

    // MARK: - Location
    private func getCurrentAddress() async -> String? {
        return await withCheckedContinuation { continuation in
            locationManager.requestLocation()

            // Simple reverse geocode
            if let location = locationManager.location {
                let geocoder = CLGeocoder()
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    if let placemark = placemarks?.first {
                        let address = [
                            placemark.name,
                            placemark.locality,
                            placemark.administrativeArea
                        ].compactMap { $0 }.joined(separator: ", ")
                        continuation.resume(returning: address)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - Escalation Payload
struct EscalationPayload: Codable {
    let contactName: String
    let contactPhone: String
    let userFirstName: String
    let timestamp: String
    let locationAddress: String
    let messageId: String
}
