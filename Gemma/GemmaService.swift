import Foundation
import MediaPipeTasksGenai

// MARK: - Gemma Service
/// On-device Gemma 2B inference service using Google AI Edge MediaPipe LLM Inference.
/// MediaPipe handles tokenization, KV cache, and sampling on-device with ANE/GPU acceleration.
/// Model format: .bin (converted via mediapipe.tasks.python.genai.converter).
/// Falls back to simulation mode when no model is bundled — app remains fully testable.
final class GemmaService: ObservableObject {
    static let shared = GemmaService()

    // MARK: - Published State
    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastDecision: InterventionType?
    @Published var lastError: Error?

    // MARK: - Model Configuration
    private let maxTokens: Int = 256
    private let temperature: Float = 0.3
    private let topk: Int = 40

    // MARK: - MediaPipe LLM Inference
    /// Live MediaPipe LLM inference session. nil when no model is bundled (simulation mode).
    private var llmInference: LlmInference?
    private let inferenceQueue = DispatchQueue(label: "com.panicguard.gemma.inference", qos: .userInitiated)

    // MARK: - Model Cache
    private var modelLoadTask: Task<Void, Never>?
    private var lastInferenceTime: Date?

    // MARK: - Initialization
    private init() {}

    // MARK: - Model Management

    /// Loads Gemma .bin model via MediaPipe LLM Inference.
    /// Falls back to simulation mode if the model file is not in the bundle.
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
        // MediaPipe model format: .bin (not .mlmodel)
        // Bundle gemma-2-2b-it-qat.bin or gemma-4-2b-it-qat.bin with the app
        guard let modelPath = Bundle.main.path(forResource: "gemma-2-2b-it-qat", ofType: "bin")
                ?? Bundle.main.path(forResource: "gemma-4-2b-it-qat", ofType: "bin") else {
            print("[GemmaService] No Gemma .bin model found in bundle — running in simulation mode")
            // Still mark loaded so simulation path works
            await MainActor.run { self.isModelLoaded = true }
            return
        }

        let options = LlmInferenceOptions()
        options.baseOptions.modelPath = modelPath
        options.maxTokens = maxTokens
        options.topk = Int32(topk)
        options.temperature = temperature

        llmInference = try LlmInference(options: options)
        print("[GemmaService] MediaPipe LLM Inference session created")
    }

    // MARK: - Inference

    /// Makes a decision based on physiological state.
    /// Returns the selected InterventionType.
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

        let prompt = GemmaPromptBuilder.buildPrompt(from: state)
        let fullPrompt = buildFullPrompt(userPrompt: prompt)

        let jsonResponse = await runInference(prompt: fullPrompt)
        let result = await processInferenceResult(jsonResponse)

        await MainActor.run {
            self.lastDecision = result
        }

        return result
    }

    /// Processes check-in response from user.
    func processUserResponse(
        _ response: String,
        originalState: GemmaPromptBuilder.PhysiologicalState
    ) async -> InterventionType {
        let analysis = GemmaDispatch.analyzeUserResponse(response)

        if analysis != .unclear {
            await MainActor.run {
                self.lastDecision = analysis.recommendedAction
            }
            return analysis.recommendedAction
        }

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

    // MARK: - Prompt Assembly

    private func buildFullPrompt(userPrompt: String) -> String {
        return """
        \(GemmaPromptBuilder.systemPrompt)

        \(userPrompt)
        """
    }

    // MARK: - Inference Engine

    /// Runs inference via MediaPipe LLM Inference, or simulation if no model is loaded.
    private func runInference(prompt: String) async -> String {
        guard isModelLoaded, let inference = llmInference else {
            return simulateInference(prompt: prompt)
        }

        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
                do {
                    let response = try inference.generateResponse(inputText: prompt)
                    self.lastInferenceTime = Date()
                    continuation.resume(returning: response)
                } catch {
                    print("[GemmaService] Inference error: \(error)")
                    continuation.resume(returning: self.simulateInference(prompt: prompt))
                }
            }
        }
    }

    /// Streaming inference — yields partial results as they're generated.
    func generateResponseStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard isModelLoaded, let inference = llmInference else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            self.inferenceQueue.async {
                do {
                    let stream = try inference.generateResponseAsync(inputText: prompt)
                    for try await partialResult in stream {
                        continuation.yield(partialResult)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Simulation Fallback

    /// Deterministic simulation when no model is bundled — makes the app fully testable.
    private func simulateInference(prompt: String) -> String {
        var simulatedConfidence = "moderate"

        if prompt.contains("confidence: 0.9") || prompt.contains("confidence: 0.8") {
            simulatedConfidence = "high"
        } else if prompt.contains("confidence: 0.3") || prompt.contains("confidence: 0.2") || prompt.contains("confidence: 0.1") {
            simulatedConfidence = "low"
        }

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

    // MARK: - Result Processing

    private func processInferenceResult(_ jsonString: String) async -> InterventionType {
        let parseResult = GemmaDispatch.parseJSONResponse(jsonString)

        switch parseResult {
        case .success(let response):
            if let interventionType = await GemmaDispatch.dispatch(response: response) {
                return interventionType
            }
            return GemmaDispatch.mapActionToInterventionType(response.action) ?? .dismiss

        case .failure(let error):
            print("[GemmaService] Parse error: \(error)")
            return heuristicFallback()
        }
    }

    private func heuristicFallback() -> InterventionType {
        guard let lastDecision = lastDecision else { return .checkIn }
        switch lastDecision {
        case .breathingExercise: return .groundingPrompt
        case .groundingPrompt: return .hapticRhythm
        case .hapticRhythm: return .checkIn
        case .checkIn: return .escalate
        default: return .dismiss
        }
    }

    // MARK: - Journal Correlator Inference

    /// Runs Gemma for journal-based trigger correlation analysis.
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

        guard isModelLoaded, let inference = llmInference else {
            return simulateJournalCorrelatorFallback()
        }

        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
                do {
                    let response = try inference.generateResponse(inputText: fullPrompt)
                    self.lastInferenceTime = Date()
                    continuation.resume(returning: response)
                } catch {
                    print("[GemmaService] Journal correlator inference error: \(error)")
                    continuation.resume(returning: self.simulateJournalCorrelatorFallback())
                }
            }
        }
    }

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

    // MARK: - Episode History

    func getRecentEpisodeContext() -> (count: Int, hoursSinceLast: Float?) {
        return EpisodeLogger().getRecentEpisodeContext()
    }

    // MARK: - Cleanup

    func preloadModel() {
        modelLoadTask = Task { await loadModel() }
    }

    deinit {
        modelLoadTask?.cancel()
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
        case .modelNotFound:    return "Gemma model file not found in bundle"
        case .inferenceFailed(let msg): return "Inference failed: \(msg)"
        case .modelNotLoaded:   return "Gemma model not yet loaded"
        case .invalidResponse:  return "Invalid response from model"
        }
    }
}

// MARK: - Integration Helpers
extension GemmaService {
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

    /// Asks Gemma to explain a trigger correlation pattern in plain language.
    func explainPattern(_ correlation: EpisodeLogger.TriggerCorrelation) async -> String {
        let prompt = GemmaPromptBuilder.buildPatternExplanationPrompt(for: correlation)
        let fullPrompt = buildFullPrompt(userPrompt: prompt)

        guard isModelLoaded, let inference = llmInference else {
            return fallbackPatternExplanation(for: correlation)
        }

        return await withCheckedContinuation { continuation in
            inferenceQueue.async {
                do {
                    let response = try inference.generateResponse(inputText: fullPrompt)
                    continuation.resume(returning: self.cleanResponse(response))
                } catch {
                    continuation.resume(returning: self.fallbackPatternExplanation(for: correlation))
                }
            }
        }
    }

    private func cleanResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
            if cleaned.hasPrefix("json") || cleaned.hasPrefix("txt") {
                cleaned = String(cleaned.dropFirst(3))
            }
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.isEmpty ? response : cleaned
    }

    private func fallbackPatternExplanation(for correlation: EpisodeLogger.TriggerCorrelation) -> String {
        switch correlation.patternType {
        case .timeOfDay:
            return "Your episodes tend to cluster around \(correlation.patternDescription). This is a common pattern in panic disorder — cortisol levels and physiological arousal follow circadian rhythms."
        case .sleepDebt:
            return "Sleep deprivation lowers your panic threshold. \(correlation.patternDescription). Prioritizing 7-9 hours of sleep is one of the most evidence-backed ways to reduce episode frequency."
        case .calendarEvent:
            return "\(correlation.patternDescription). The anticipation anxiety before events like work meetings can be a significant trigger. Grounding exercises before these events may help."
        case .journalTheme:
            return "Your journal entries suggest \(correlation.patternDescription). This theme has appeared in \(correlation.episodeCount) of your recent episodes."
        case .exerciseContext:
            return "\(correlation.patternDescription). Exercise is generally protective, but high-intensity exercise immediately after a stressful period can occasionally trigger episodes."
        case .none, .exerciseContext:
            return "This pattern shows \(correlation.patternDescription). Keep tracking — patterns become clearer with more data."
        }
    }
}
