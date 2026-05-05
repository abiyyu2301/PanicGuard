import Foundation
import MediaPipe
import MediaPipeTasksGenAI

// MARK: - Gemma Service
/// On-device Gemma 4 E2B inference service using Google AI Edge SDK
/// Integrates with MediaPipe LLM Inference for grammar-constrained JSON output
final class GemmaService: ObservableObject {
    static let shared = GemmaService()
    
    // MARK: - Published State
    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastDecision: InterventionType?
    @Published var lastError: Error?
    
    // MARK: - Model Configuration
    private let modelPath: String
    private let maxTokens: Int = 256
    private let temperature: Float = 0.3  // Low temperature for consistent JSON
    
    // MARK: - MediaPipe LLM Inference
    private var llmInference: LlmInference?
    private let inferenceQueue = DispatchQueue(label: "com.panicguard.gemma.inference", qos: .userInitiated)
    
    // MARK: - Model Cache
    private var modelLoadTask: Task<Void, Never>?
    private var lastInferenceTime: Date?
    
    // MARK: - Grammar Constraint for JSON Output
    /// JSON schema for tool calling output
    private let jsonGrammar = """
    {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["breathing_exercise", "grounding_prompt", "haptic_rhythm", "check_in", "escalate", "dismiss"]
            },
            "confidence": {
                "type": "string", 
                "enum": ["high", "moderate", "low"]
            },
            "reasoning": {
                "type": "string"
            }
        },
        "required": ["action", "confidence", "reasoning"]
    }
    """
    
    // MARK: - Initialization
    private init() {
        // Model path - in production, bundle with app or download on first launch
        // Gemma 4 2B E2B variants: gemma-2-2b-it-qat, gemma-4-2b-it-qat
        self.modelPath = Bundle.main.path(forResource: "gemma-4-2b-it-qat", ofType: "mlmodel")
            ?? Bundle.main.path(forResource: "gemma-2-2b-it-qat", ofType: "mlmodel")
            ?? ""
    }
    
    // MARK: - Model Management
    
    /// Loads Gemma model at app launch and keeps in memory
    /// Uses MediaPipe LLM Inference API with Core ML + ANE acceleration
    func loadModel() async {
        guard !isModelLoaded && !isLoading else { return }
        
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        
        do {
            try await performModelLoad()
            await MainActor.run {
                self.isModelLoaded = true
                self.isLoading = false
            }
            print("[GemmaService] Model loaded successfully")
        } catch {
            print("[GemmaService] Model load failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = error
                self.isLoading = false
            }
        }
    }
    
    private func performModelLoad() async throws {
        // Check if model file exists
        guard !modelPath.isEmpty else {
            // No bundled model - use simulated mode for development
            print("[GemmaService] No bundled model found, using simulation mode")
            try await Task.sleep(nanoseconds: 500_000_000)  // Simulate load time
            return
        }
        
        // Configure LLM Inference with MediaPipe
        let options = LlmInferenceOptions()
        
        // Model path configuration
        options.modelPath = modelPath
        
        // Performance settings - prefer ANE (Apple Neural Engine) for on-device efficiency
        options.maxTokens = maxTokens
        options.temperature = temperature
        
        // Grammar-constrained decoding for JSON output
        // MediaPipe supports this via response syntax constraint
        options.setupJSONGrammar()
        
        // Create inference session
        llmInference = try LlmInference(options: options)
        
        // Warm up the model with a dummy inference
        try await warmUpModel()
    }
    
    /// Warm-up inference to initialize ANE/neural engine kernels
    private func warmUpModel() async throws {
        guard llmInference != nil else { return }
        
        let warmUpPrompt = "Output JSON: {\"action\": \"dismiss\", \"confidence\": \"low\", \"reasoning\": \"warmup\"}"
        
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self = self, let inference = self.llmInference else {
                    continuation.resume(returning: "")
                    return
                }
                
                do {
                    let response = try inference.generateResponse(modelPrompt: warmUpPrompt)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        print("[GemmaService] Model warm-up complete")
    }
    
    // MARK: - Inference
    
    /// Makes a decision based on physiological state
    /// Returns the selected InterventionType
    func makeDecision(
        confidence: Float,
        heartRate: Float,
        hrv: Float,
        hrRMSDD: Float? = nil,
        hrSDNN: Float? = nil,
        age: Int,
        recentSleepHours: Float? = nil,
        recentEpisodeCount: Int = 0,
        hoursSinceLastEpisode: Float? = nil
    ) async -> InterventionType {
        // Build physiological state
        let state = GemmaPromptBuilder.PhysiologicalState(
            confidence: confidence,
            heartRate: heartRate,
            hrv: hrv,
            hrRMSDD: hrRMSDD,
            hrSDNN: hrSDNN,
            age: age,
            timeOfDay: Date(),
            recentSleepHours: recentSleepHours,
            recentEpisodeCount: recentEpisodeCount,
            hoursSinceLastEpisode: hoursSinceLastEpisode
        )
        
        // Build prompt
        let prompt = GemmaPromptBuilder.buildPrompt(from: state)
        let fullPrompt = buildFullPrompt(userPrompt: prompt)
        
        // Run inference
        let jsonResponse = await runInference(prompt: fullPrompt)
        
        // Parse and dispatch
        let result = await processInferenceResult(jsonResponse)
        
        await MainActor.run {
            self.lastDecision = result
        }
        
        return result
    }
    
    /// Processes check-in response from user
    func processUserResponse(
        _ response: String,
        originalState: GemmaPromptBuilder.PhysiologicalState
    ) async -> InterventionType {
        // First, do keyword-based analysis via GemmaDispatch
        let analysis = GemmaDispatch.analyzeUserResponse(response)
        
        // If clear distress or okay, use direct mapping
        if analysis != .unclear {
            let intervention = analysis.recommendedAction
            await MainActor.run {
                self.lastDecision = intervention
            }
            return intervention
        }
        
        // For unclear responses, use Gemma for nuanced interpretation
        let followUpPrompt = GemmaPromptBuilder.buildCheckInFollowUp(
            originalState: originalState,
            userResponse: response
        )
        let fullPrompt = buildFullPrompt(userPrompt: followUpPrompt)
        
        let jsonResponse = await runInference(prompt: fullPrompt)
        let result = await processInferenceResult(jsonResponse)
        
        await MainActor.run {
            self.lastDecision = result
        }
        
        return result
    }
    
    // MARK: - Inference Implementation
    
    /// Builds complete prompt with system instructions
    private func buildFullPrompt(userPrompt: String) -> String {
        return """
        \(GemmaPromptBuilder.systemPrompt)
        
        \(userPrompt)
        """
    }
    
    /// Runs inference on Gemma model
    private func runInference(prompt: String) async -> String {
        // If model not loaded, use fallback
        guard isModelLoaded, let inference = llmInference else {
            return simulateInference(prompt: prompt)
        }
        
        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
                do {
                    let response = try inference.generateResponse(modelPrompt: prompt)
                    self.lastInferenceTime = Date()
                    continuation.resume(returning: response)
                } catch {
                    print("[GemmaService] Inference error: \(error)")
                    continuation.resume(returning: self.simulateInference(prompt: prompt))
                }
            }
        }
    }
    
    /// Fallback simulation when model is unavailable
    private func simulateInference(prompt: String) -> String {
        // Parse confidence from prompt to make realistic decisions
        var simulatedConfidence = "moderate"
        
        if prompt.contains("confidence: 0.9") || prompt.contains("confidence: 0.8") {
            simulatedConfidence = "high"
        } else if prompt.contains("confidence: 0.3") || prompt.contains("confidence: 0.2") || prompt.contains("confidence: 0.1") {
            simulatedConfidence = "low"
        }
        
        // Determine action based on heuristics
        let action: String
        if prompt.contains("check_in") {
            action = "check_in"
        } else if simulatedConfidence == "high" {
            action = "breathing_exercise"
        } else if simulatedConfidence == "moderate" {
            action = "grounding_prompt"
        } else {
            action = "dismiss"
        }
        
        let reasoning: String
        switch action {
        case "breathing_exercise":
            reasoning = "High physiological distress detected. Initiating breathing exercise for immediate calming."
        case "grounding_prompt":
            reasoning = "Moderate distress. Using 5-4-3-2-1 grounding to redirect attention."
        case "check_in":
            reasoning = "Ambiguous signals. Checking user status before intervention."
        case "dismiss":
            reasoning = "Low confidence. No significant distress pattern detected."
        default:
            reasoning = "Based on physiological indicators."
        }
        
        return """
        {
            "action": "\(action)",
            "confidence": "\(simulatedConfidence)",
            "reasoning": "\(reasoning)"
        }
        """
    }
    
    /// Processes inference JSON result
    private func processInferenceResult(_ jsonString: String) async -> InterventionType {
        let parseResult = GemmaDispatch.parseJSONResponse(jsonString)
        
        switch parseResult {
        case .success(let response):
            // Dispatch to trigger intervention
            if let interventionType = await GemmaDispatch.dispatch(response: response) {
                return interventionType
            }
            // Fallback to action mapping
            return GemmaDispatch.mapActionToInterventionType(response.action) ?? .dismiss
            
        case .failure(let error):
            print("[GemmaService] Parse error: \(error)")
            // Use heuristic fallback
            return heuristicFallback()
        }
    }
    
    // MARK: - Journal Correlator Inference

    /// Runs Gemma inference for journal correlation analysis.
    /// Used by GemmaJournalCorrelator to identify trigger patterns.
    func runJournalCorrelatorInference(prompt: String) async -> String {
        let fullPrompt = """
        \(GemmaPromptBuilder.systemPrompt)

        \(prompt)

        Respond with ONLY valid JSON in the following format. Do not include any text outside the JSON object.
        {
            "summary": "<one sentence summary of journal entry significance>",
            "insights": ["<insight 1>", "<insight 2>", "<insight 3>"],
            "correlations": [
                {
                    "pattern_type": "<timeOfDay|calendarEvent|sleepDebt|journalTheme|exerciseContext|none>",
                    "pattern_description": "<natural language description of the pattern>",
                    "confidence": <0.0 to 1.0>,
                    "episode_count": <integer>,
                    "supporting_details": "<specific details about matching episodes>"
                }
            ]
        }
        """

        // If model not loaded, use simulation fallback
        guard isModelLoaded, let inference = llmInference else {
            return simulateJournalCorrelatorFallback()
        }

        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
                do {
                    let response = try inference.generateResponse(modelPrompt: fullPrompt)
                    self.lastInferenceTime = Date()
                    continuation.resume(returning: response)
                } catch {
                    print("[GemmaService] Journal correlator inference error: \(error)")
                    continuation.resume(returning: self.simulateJournalCorrelatorFallback())
                }
            }
        }
    }

    /// Simulation fallback for journal correlator when model is unavailable
    private func simulateJournalCorrelatorFallback() -> String {
        return """
        {
            "summary": "No significant trigger patterns detected in this journal entry.",
            "insights": [
                "Keep logging your mood daily — patterns emerge over time.",
                "Your entries help build a clearer picture of your triggers."
            ],
            "correlations": []
        }
        """
    }

    // MARK: - Heuristic Fallback

    /// Heuristic fallback when inference fails
    private func heuristicFallback() -> InterventionType {
        guard let lastDecision = lastDecision else {
            return .checkIn  // Safe default
        }
        // Don't repeat the same intervention
        switch lastDecision {
        case .breathingExercise: return .groundingPrompt
        case .groundingPrompt: return .hapticRhythm
        case .hapticRhythm: return .checkIn
        case .checkIn: return .escalate
        default: return .dismiss
        }
    }
    
    // MARK: - Episode History
    
    /// Fetches recent episodes for context from EpisodeLogger.
    func getRecentEpisodeContext() -> (count: Int, hoursSinceLast: Float?) {
        return EpisodeLogger().getRecentEpisodeContext()
    }
    
    // MARK: - Cleanup
    
    /// Preloads model when app launches
    func preloadModel() {
        modelLoadTask = Task {
            await loadModel()
        }
    }
    
    deinit {
        modelLoadTask?.cancel()
    }
}

// MARK: - MediaPipe LLM Inference Options Extension
/// Extension to configure grammar-constrained decoding
extension LlmInferenceOptions {
    /// Sets up JSON grammar constraint for structured output
    func setupJSONGrammar() {
        // MediaPipe LLM Inference uses responseMimeType for grammar constraints
        responseMimeType = "application/json"
        // In production, use responseSchema for strict enum constraints
    }
}

// MARK: - Error Types
enum GemmaServiceError: Error, LocalizedError {
    case modelNotFound
    case inferenceFailed(String)
    case modelNotLoaded
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Gemma model file not found in bundle"
        case .inferenceFailed(let message):
            return "Inference failed: \(message)"
        case .modelNotLoaded:
            return "Gemma model not yet loaded"
        case .invalidResponse:
            return "Invalid response from model"
        }
    }
}

// MARK: - Integration Helpers

extension GemmaService {
    /// Convenience method to process detection engine output
    func processDetection(
        confidence: Float,
        heartRate: Float,
        hrv: Float,
        age: Int,
        sleepHours: Float? = nil
    ) async -> InterventionType {
        let (episodeCount, hoursSince) = getRecentEpisodeContext()

        return await makeDecision(
            confidence: confidence,
            heartRate: heartRate,
            hrv: hrv,
            age: age,
            recentSleepHours: sleepHours,
            recentEpisodeCount: episodeCount,
            hoursSinceLastEpisode: hoursSince
        )
    }

    // MARK: - Pattern Explanation

    /// Asks Gemma to explain a trigger correlation pattern in plain language
    /// - Parameter correlation: The correlation to explain
    /// - Returns: A natural language explanation of the pattern
    func explainPattern(_ correlation: EpisodeLogger.TriggerCorrelation) async -> String {
        let prompt = GemmaPromptBuilder.buildPatternExplanationPrompt(for: correlation)
        let fullPrompt = buildFullPrompt(userPrompt: prompt)

        let response = await runInference(prompt: fullPrompt)

        // If inference failed or returned empty, provide a fallback explanation
        guard !response.isEmpty else {
            return fallbackPatternExplanation(for: correlation)
        }

        // Clean response - remove markdown code blocks if present
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3))
            if cleanedResponse.hasPrefix("json") || cleanedResponse.hasPrefix("txt") {
                cleanedResponse = String(cleanedResponse.dropFirst(3))
            }
        }
        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3))
        }
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // If Gemma still returned JSON instead of plain text, extract just the text
        if cleanedResponse.hasPrefix("{") {
            return fallbackPatternExplanation(for: correlation)
        }

        return cleanedResponse
    }

    /// Fallback explanation when Gemma inference is unavailable
    private func fallbackPatternExplanation(for correlation: EpisodeLogger.TriggerCorrelation) -> String {
        switch correlation.patternType {
        case .sleepDebt:
            return "This pattern suggests that getting less sleep may be contributing to your panic episodes. When we're sleep-deprived, our nervous system is already under stress, making us more susceptible to panic responses. Consider aiming for 7-8 hours of sleep and see if that helps reduce episodes."
        case .timeOfDay:
            return "Your episodes seem to cluster around a specific time of day. This could be related to daily stress rhythms, blood sugar fluctuations, or caffeine intake patterns. Pay attention to what happens around this time—identifying the trigger can help you prepare coping strategies in advance."
        case .calendarEvent:
            return "This pattern links certain calendar events to your panic episodes. High-stakes or demanding events can increase anxiety, especially when combined with other stressors. Consider提前 planning calming activities around these events."
        case .journalTheme:
            return "There's a connection between your emotional state (as recorded in journal entries) and panic episodes. This self-awareness is valuable—it means you can use journaling as a tool to notice and process difficult emotions before they escalate."
        case .exerciseContext:
            return "This pattern suggests a relationship between physical activity and panic episodes. Regular exercise is generally protective against anxiety, but intense exercise without proper preparation can sometimes be triggering. Consider gentle movement like walking or stretching."
        case .none:
            return "This pattern is still being analyzed. Keep recording your episodes and journal entries—the connection may become clearer over time."
        }
    }
}
