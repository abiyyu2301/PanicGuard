import Foundation
import WatchConnectivity
import WatchKit

/// Haptic pattern types that can be sent to Apple Watch
enum WatchHapticPattern: String, Codable {
    case calmRhythm = "calm_rhythm"       // 3 pulses, 0.5s interval, 4x repeat
    case notification = "notification"   // Standard watch notification haptic
    case gentlePulse = "gentle_pulse"     // Single gentle pulse
}

/// Message keys for WatchConnectivity communication
private enum MessageKey {
    static let hapticPattern = "haptic_pattern"
    static let hapticParameters = "haptic_parameters"
    static let timestamp = "timestamp"
    static let confirmation = "confirmation"
    static let confirmationStatus = "status"
}

/// Service for routing haptic patterns to Apple Watch via WatchConnectivity framework
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()
    
    /// Indicates whether the Watch session is active and reachable
    private(set) var isSessionActive: Bool = false
    
    /// Indicates whether the paired Watch is reachable
    var isWatchReachable: Bool {
        return WCSession.default.isReachable
    }
    
    /// Indicates whether a Watch is paired
    var isWatchPaired: Bool {
        return WCSession.default.isPaired
    }
    
    private var session: WCSession?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Session Management
    
    /// Starts and activates the WatchConnectivity session
    /// Call this on app launch to establish connection with paired Watch
    func startSession() {
        guard WCSession.isSupported() else {
            print("WatchConnectivityService: WatchConnectivity is not supported on this device")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
        
        print("WatchConnectivityService: Session activation requested")
    }
    
    /// Activates the WatchConnectivity session with completion handler
    /// - Parameter completion: Called when activation completes with success status
    func startSession(completion: @escaping (Bool) -> Void) {
        guard WCSession.isSupported() else {
            print("WatchConnectivityService: WatchConnectivity is not supported on this device")
            completion(false)
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        
        session?.activate { [weak self] activationError in
            DispatchQueue.main.async {
                if let error = activationError {
                    print("WatchConnectivityService: Activation failed - \(error.localizedDescription)")
                    self?.isSessionActive = false
                    completion(false)
                } else {
                    self?.isSessionActive = true
                    print("WatchConnectivityService: Session activated successfully")
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Haptic Sending
    
    /// Sends a haptic pattern to the Apple Watch
    /// - Parameter pattern: The haptic pattern to send
    /// - Returns: Boolean indicating if the send was attempted (not guaranteed delivery)
    @discardableResult
    func sendHaptic(pattern: WatchHapticPattern) -> Bool {
        guard isSessionActive else {
            print("WatchConnectivityService: Cannot send haptic - session not active. Call startSession() first.")
            return false
        }
        
        guard isWatchPaired else {
            print("WatchConnectivityService: Cannot send haptic - no Watch paired")
            return false
        }
        
        guard isWatchReachable else {
            print("WatchConnectivityService: Cannot send haptic - Watch not reachable. Message will be queued.")
            // Even if not reachable, we can still send via transferUserInfo for guaranteed delivery
            sendHapticUnreached(pattern: pattern)
            return false
        }
        
        return sendReachableHaptic(pattern: pattern)
    }
    
    /// Sends haptic to reachable Watch using sendMessage
    private func sendReachableHaptic(pattern: WatchHapticPattern) -> Bool {
        let message: [String: Any] = [
            MessageKey.hapticPattern: pattern.rawValue,
            MessageKey.timestamp: Date().timeIntervalSince1970
        ]
        
        session?.sendMessage(message, replyHandler: { [weak self] reply in
            self?.handleWatchConfirmation(reply)
        }, errorHandler: { error in
            print("WatchConnectivityService: Failed to send haptic - \(error.localizedDescription)")
        })
        
        print("WatchConnectivityService: Sent haptic pattern '\(pattern.rawValue)' to Watch")
        return true
    }
    
    /// Sends haptic via transferUserInfo when Watch is not immediately reachable
    private func sendHapticUnreached(pattern: WatchHapticPattern) {
        let userInfo: [String: Any] = [
            MessageKey.hapticPattern: pattern.rawValue,
            MessageKey.timestamp: Date().timeIntervalSince1970
        ]
        
        session?.transferUserInfo(userInfo)
        print("WatchConnectivityService: Queued haptic pattern '\(pattern.rawValue)' for delivery")
    }
    
    /// Sends the calm rhythm haptic pattern (3 pulses, 0.5s interval, 4x repeat)
    /// This matches the pattern used by HapticService for local haptics
    func sendCalmRhythm() {
        sendHaptic(pattern: .calmRhythm)
    }
    
    /// Sends a notification haptic to the Watch
    func sendNotificationHaptic() {
        sendHaptic(pattern: .notification)
    }
    
    /// Sends a gentle pulse haptic to the Watch
    func sendGentlePulse() {
        sendHaptic(pattern: .gentlePulse)
    }
    
    // MARK: - Message Handling
    
    /// Handles messages received from the Watch
    /// Called by WCSessionDelegate when a message is received
    func handleWatchMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        print("WatchConnectivityService: Received message from Watch - \(message)")
        
        // Check if this is a haptic confirmation
        if let confirmation = message[MessageKey.confirmation] as? [String: Any],
           let status = confirmation[MessageKey.confirmationStatus] as? String {
            handleHapticConfirmation(status: status)
            replyHandler?(["received": true])
            return
        }
        
        // Handle other message types as needed
        if let pattern = message[MessageKey.hapticPattern] as? String {
            print("WatchConnectivityService: Watch requested haptic pattern: \(pattern)")
            // Could forward to HapticService if iPhone should also play
            replyHandler?(["received": true, "pattern": pattern])
        }
    }
    
    /// Handles confirmation reply from Watch after haptic was played
    private func handleWatchConfirmation(_ reply: [String: Any]) {
        if let status = reply[MessageKey.confirmationStatus] as? String {
            handleHapticConfirmation(status: status)
        }
    }
    
    /// Processes haptic confirmation status
    private func handleHapticConfirmation(status: String) {
        switch status {
        case "played":
            print("WatchConnectivityService: Watch confirmed haptic playback")
        case "failed":
            print("WatchConnectivityService: Watch reported haptic playback failed")
        case "unsupported":
            print("WatchConnectivityService: Watch does not support requested haptic")
        default:
            print("WatchConnectivityService: Unknown confirmation status: \(status)")
        }
    }
    
    // MARK: - Utility
    
    /// Plays a haptic directly on the Watch (for use when this device is the Watch)
    /// This would be called by the Watch-side app
    static func playHapticOnWatch(pattern: WatchHapticPattern) {
        let device = WKInterfaceDevice.current()
        
        switch pattern {
        case .notification:
            device.play(.notification)
        case .gentlePulse:
            device.play(.click)
        case .calmRhythm:
            // Play 3 pulses with 0.5s interval, 4x repeat
            // Note: WatchKit has limited haptic support, so we approximate
            playCalmRhythmOnWatch(device: device)
        }
    }
    
    /// Plays the calm rhythm pattern on Watch (approximated with available haptics)
    private static func playCalmRhythmOnWatch(device: WKInterfaceDevice) {
        // WatchKit doesn't have the same CoreHaptics support as iPhone
        // We approximate with multiple clicks
        for _ in 0..<4 {
            device.play(.click)
            // Small delay between pulses - in real implementation use timeline
        }
    }
    
    /// Returns a human-readable status description
    func getStatusDescription() -> String {
        if !WCSession.isSupported() {
            return "WatchConnectivity not supported"
        }
        if !isWatchPaired {
            return "No Watch paired"
        }
        if !isSessionActive {
            return "Session inactive"
        }
        if !isWatchReachable {
            return "Watch not reachable (messages will queue)"
        }
        return "Connected and reachable"
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                print("WatchConnectivityService: Session activation failed - \(error.localizedDescription)")
                self?.isSessionActive = false
                return
            }
            
            self?.isSessionActive = (activationState == .activated)
            
            switch activationState {
            case .activated:
                print("WatchConnectivityService: Session activated (state: .activated)")
            case .inactive:
                print("WatchConnectivityService: Session inactive (state: .inactive)")
            case .notActivated:
                print("WatchConnectivityService: Session not activated (state: .notActivated)")
            @unknown default:
                print("WatchConnectivityService: Unknown activation state")
            }
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WatchConnectivityService: Session became inactive")
        DispatchQueue.main.async { [weak self] in
            self?.isSessionActive = false
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WatchConnectivityService: Session deactivated")
        DispatchQueue.main.async { [weak self] in
            self?.isSessionActive = false
        }
        // Reactivate for iOS
        session.activate()
    }
    #endif
    
    // MARK: - Message Receiving
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWatchMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWatchMessage(message, replyHandler: replyHandler)
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWatchMessage(userInfo)
        }
    }
    
    // MARK: - Reachability Changes
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            let isReachable = session.isReachable
            print("WatchConnectivityService: Reachability changed - Watch now \(isReachable ? "reachable" : "not reachable")")
            
            if isReachable {
                // Send any queued haptics when Watch becomes reachable
                print("WatchConnectivityService: Watch became reachable")
            }
        }
    }
}
