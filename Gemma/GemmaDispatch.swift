import Foundation

// MARK: - Gemma Dispatch
/// Handles JSON parsing from Gemma 4 E2B responses and action dispatch
/// to the appropriate intervention services
final class GemmaDispatch {
    
    // MARK: - Parsed Response
    struct GemmaResponse: Codable {
        let action: String
        let confidence: String
        let reasoning: String
    }
    
    // MARK: - Action Mapping
    /// Maps Gemma action strings to InterventionType
    static func mapActionToInterventionType(_ action: String) -> InterventionType? {
        switch action.lowercased() {
        case "breathing_exercise", "breathingexercise", "breathing":
            return .breathingExercise
        case "grounding_prompt", "groundingprompt", "grounding":
            return .groundingPrompt
        case "haptic_rhythm", "hapticrhythm", "haptic":
            return .hapticRhythm
        case "check_in", "checkin", "check_in_prompt":
            return .checkIn
        case "escalate", "escalation":
            return .escalate
        case "dismiss", "none", "no_intervention":
            return .dismiss
        default:
            return nil
        }
    }
    
    // MARK: - JSON Parsing
    
    /// Parse Gemma's JSON response string into GemmaResponse
    static func parseJSONResponse(_ jsonString: String) -> Result<GemmaResponse, DispatchError> {
        // Clean the response - remove markdown code blocks if present
        var cleanedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ```json and ``` markers
        if cleanedString.hasPrefix("```json") {
            cleanedString = String(cleanedString.dropFirst(7))
        } else if cleanedString.hasPrefix("```") {
            cleanedString = String(cleanedString.dropFirst(3))
        }
        
        if cleanedString.hasSuffix("```") {
            cleanedString = String(cleanedString.dropLast(3))
        }
        
        cleanedString = cleanedString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract JSON object if there's surrounding text
        if let jsonRange = cleanedString.range(of: "{", options: .backwardsSearch),
           let endRange = cleanedString.range(of: "}", options: .backwardsSearch) {
            cleanedString = String(cleanedString[jsonRange.lowerBound...endRange.upperBound])
        }
        
        // Parse JSON
        guard let data = cleanedString.data(using: .utf8) else {
            return .failure(.encodingError)
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(GemmaResponse.self, from: data)
            return .success(response)
        } catch {
            // Try to extract fields individually if full JSON fails
            return extractFieldsFromPartialJSON(cleanedString)
        }
    }
    
    /// Fallback parser for partial/malformed JSON
    private static func extractFieldsFromPartialJSON(_ string: String) -> Result<GemmaResponse, DispatchError> {
        var action: String?
        var confidence: String?
        var reasoning: String?
        
        // Extract action
        if let actionRange = string.range(of: "\"action\"", options: .caseInsensitive) {
            let afterKey = String(string[actionRange.upperBound...])
            if let colonRange = afterKey.range(of: ":") {
                var value = String(afterKey[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") { value = String(value.dropFirst()) }
                if let endQuote = value.range(of: "\"") {
                    action = String(value[..<endQuote.lowerBound])
                } else if let comma = value.range(of: ",") {
                    action = String(value[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Extract confidence
        if let confRange = string.range(of: "\"confidence\"", options: .caseInsensitive) {
            let afterKey = String(string[confRange.upperBound...])
            if let colonRange = afterKey.range(of: ":") {
                var value = String(afterKey[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") { value = String(value.dropFirst()) }
                if let endQuote = value.range(of: "\"") {
                    confidence = String(value[..<endQuote.lowerBound])
                } else if let comma = value.range(of: ",") {
                    confidence = String(value[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Extract reasoning
        if let reasonRange = string.range(of: "\"reasoning\"", options: .caseInsensitive) {
            let afterKey = String(string[reasonRange.upperBound...])
            if let colonRange = afterKey.range(of: ":") {
                var value = String(afterKey[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") { value = String(value.dropFirst()) }
                if let endQuote = value.range(of: "\"") {
                    reasoning = String(value[..<endQuote.lowerBound])
                } else if let comma = value.range(of: ",") {
                    reasoning = String(value[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        guard let actionValue = action else {
            return .failure(.missingField(field: "action"))
        }
        
        return .success(GemmaResponse(
            action: actionValue,
            confidence: confidence ?? "unknown",
            reasoning: reasoning ?? ""
        ))
    }
    
    // MARK: - Distress Detection
    
    /// Keywords indicating user distress in check-in responses
    static let distressKeywords: Set<String> = [
        "help", "scared", "panic", "can't breathe", "terrified", "anxious",
        "worst", "die", "dying", "heart attack", "freaking out", "freaked",
        "overwhelm", "losing control", "going crazy", "unbearable",
        "emergency", "911", "ambulance", "please help", "sos"
    ]
    
    /// Keywords indicating user is okay
    static let okKeywords: Set<String> = [
        "okay", "ok", "fine", "good", "better", "great", "awesome",
        "calm", "relaxed", "dismiss", "no thanks", "i'm fine", "im fine",
        "feeling better", "better now", "ok now"
    ]
    
    /// Analyzes user response text for distress signals
    static func analyzeUserResponse(_ response: String) -> ResponseAnalysis {
        let lowercased = response.lowercased()
        
        // Check for distress keywords
        var distressScore = 0
        for keyword in distressKeywords {
            if lowercased.contains(keyword) {
                distressScore += 1
            }
        }
        
        // Check for OK keywords
        var okScore = 0
        for keyword in okKeywords {
            if lowercased.contains(keyword) {
                okScore += 1
            }
        }
        
        // Analyze exclamation and capitalization for urgency
        let hasExclamation = response.contains("!")
        let hasCapsLock = response.filter { $0.isUppercase }.count > response.count / 3
        
        // Determine result
        if distressScore >= 2 || (distressScore >= 1 && (hasExclamation || hasCapsLock)) {
            return .distressed
        } else if okScore >= 1 {
            return .okay
        } else {
            return .unclear
        }
    }
    
    enum ResponseAnalysis {
        case distressed
        case okay
        case unclear
        
        var recommendedAction: InterventionType {
            switch self {
            case .distressed: return .escalate
            case .okay: return .dismiss
            case .unclear: return .groundingPrompt
            }
        }
    }
    
    // MARK: - Check-In Management
    
    /// Manages check-in state with 60-second timeout
    final class CheckInManager: ObservableObject {
        static let shared = CheckInManager()
        
        @Published var isAwaitingResponse: Bool = false
        @Published var checkInStartTime: Date?
        
        private var timeoutTask: Task<Void, Never>?
        private let checkInTimeoutSeconds: TimeInterval = 60.0
        
        private init() {}
        
        /// Starts the 60-second check-in timeout
        func startCheckIn() {
            isAwaitingResponse = true
            checkInStartTime = Date()
            
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(checkInTimeoutSeconds * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                
                if self.isAwaitingResponse {
                    self.isAwaitingResponse = false
                    self.timeoutTask = nil
                    NotificationCenter.default.post(
                        name: .checkInTimeout,
                        object: nil
                    )
                }
            }
        }
        
        /// Cancels the check-in (user responded or intervention triggered)
        func cancelCheckIn() {
            timeoutTask?.cancel()
            timeoutTask = nil
            isAwaitingResponse = false
            checkInStartTime = nil
        }
        
        /// Returns remaining time in the check-in window
        var remainingTime: TimeInterval? {
            guard let startTime = checkInStartTime else { return nil }
            let elapsed = Date().timeIntervalSince(startTime)
            return max(0, checkInTimeoutSeconds - elapsed)
        }
    }
    
    // MARK: - Dispatch Errors
    enum DispatchError: Error, LocalizedError {
        case encodingError
        case missingField(field: String)
        case invalidAction(String)
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .encodingError:
                return "Failed to encode response string"
            case .missingField(let field):
                return "Missing required field: \(field)"
            case .invalidAction(let action):
                return "Invalid action: \(action)"
            case .timeout:
                return "Check-in response timed out"
            }
        }
    }
    
    // MARK: - Action Dispatcher
    
    /// Dispatches Gemma's decision to the appropriate service
    @MainActor
    static func dispatch(
        response: GemmaResponse,
        to coordinator: PanicGuardCoordinator? = nil
    ) -> InterventionType? {
        guard let interventionType = mapActionToInterventionType(response.action) else {
            print("[GemmaDispatch] Unknown action: \(response.action)")
            return nil
        }
        
        print("[GemmaDispatch] Action: \(interventionType.rawValue) (\(response.confidence))")
        print("[GemmaDispatch] Reasoning: \(response.reasoning)")
        
        // Notify coordinator to trigger intervention
        NotificationCenter.default.post(
            name: .gemmaDecision,
            object: nil,
            userInfo: [
                "interventionType": interventionType,
                "confidence": response.confidence,
                "reasoning": response.reasoning
            ]
        )
        
        return interventionType
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let gemmaDecision = Notification.Name("gemmaDecision")
    static let checkInTimeout = Notification.Name("checkInTimeout")
}

// MARK: - Panic Guard Coordinator Reference
/// Reference to coordinator needed for dispatch - will be resolved via NotificationCenter
/// or dependency injection in production
protocol PanicGuardCoordinator {
    func triggerIntervention(_ type: InterventionType)
    func escalateToEmergency(reason: String)
}
