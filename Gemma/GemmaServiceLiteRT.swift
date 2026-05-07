import Foundation

// MARK: - Gemma Service (LiteRT Backend)
/// On-device Gemma 4 2B inference service using LiteRT-LM C++ runtime.
/// Replaces the deprecated `MediaPipeTasksGenai` stack.
///
/// Model format: `.litertlm` — converted from GGUF via
/// `bazel run //tools:litert_lm_builder` or downloaded pre-converted.
///
/// Falls back to simulation mode when no model is bundled — app remains fully testable.
///
/// ## Migration from MediaPipe
/// - `LlmInference` → `LiteRTModel`
/// - `generateResponse(inputText:)` → `generateResponse(prompt:)`
/// - `generateResponseAsync(inputText:)` → `generateResponseAsync(prompt:)`
/// - All prompt builders (`GemmaPromptBuilder`, `GemmaDispatch`) remain unchanged.
final class GemmaServiceLiteRT: ObservableObject {
    static let shared = GemmaServiceLiteRT()

    // MARK: - Published State
    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastDecision: InterventionType?
    @Published var lastError: Error?

    // MARK: - Model Configuration
    private let maxTokens: Int = 256
    private let temperature: Float = 0.3
    private let topk: Int = 40

    // MARK: - LiteRT Model
    /// Live LiteRT model instance. nil when no model is bundled (simulation mode).
    private var model: LiteRTModel?
    private let modelQueue = DispatchQueue(label: "com.panicguard.gemma.litert.load", qos: .userInitiated)

    // MARK: - Model Cache
    private var modelLoadTask: Task<Void, Never>?
    private var lastInferenceTime: Date?

    // MARK: - Initialization
    private init() {}

    // MARK: - Model Management

    /// Loads Gemma `.litertlm` model via LiteRT-LM.
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
            print("[GemmaServiceLiteRT] Model loaded successfully")
        } catch {
            print("[GemmaServiceLiteRT] Model load failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = error
                self.isLoading = false
            }
        }
    }

    private func performModelLoad() async throws {
        // LiteRT model format: .litertlm
        // Bundle gemma-4-E2B-it.litertlm with the app
        guard let modelPath = LiteRTModel.modelPathInBundle(
            "gemma-4-E2B-it",
            extension: "litertlm"
        ) else {
            print("[GemmaServiceLiteRT] No Gemma .litertlm model found in bundle — running in simulation mode")
            // Still mark loaded so simulation path works
            await MainActor.run { self.isModelLoaded = true }
            return
        }

        let litertModel = LiteRTModel(
            maxOutputTokens: maxTokens,
            temperature: temperature,
            topK: topk,
            backend: "metal"  // GPU acceleration on iOS
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            modelQueue.async {
                do {
                    try litertModel.loadModel(from: modelPath)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        self.model = litertModel
        print("[GemmaServiceLiteRT] LiteRT model session ready at \(modelPath)")
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

    /// Runs inference via LiteRT, or simulation if no model is loaded.
    private func runInference(prompt: String) async -> String {
        guard isModelLoaded, let model = model else {
            return simulateInference(prompt: prompt)
        }

        do {
            let response = try await model.generateResponseAsync(prompt: prompt)
            lastInferenceTime = Date()
            return response
        } catch {
            print("[GemmaServiceLiteRT] Inference error: \(error)")
            return simulateInference(prompt: prompt)
        }
    }

    /// Streaming inference — yields partial results as they're generated.
    func generateResponseStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard isModelLoaded, let model = model else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return model.generateResponseStream(prompt: prompt)
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
            print("[GemmaServiceLiteRT] Parse error: \(error)")
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

        guard isModelLoaded, let model = model else {
            return simulateJournalCorrelatorFallback()
        }

        do {
            let response = try await model.generateResponseAsync(prompt: fullPrompt)
            lastInferenceTime = Date()
            return response
        } catch {
            print("[GemmaServiceLiteRT] Journal correlator inference error: \(error)")
            return simulateJournalCorrelatorFallback()
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

// MARK: - Integration Helpers
extension GemmaServiceLiteRT {
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

        guard isModelLoaded, let model = model else {
            return fallbackPatternExplanation(for: correlation)
        }

        do {
            let response = try await model.generateResponseAsync(prompt: fullPrompt)
            return cleanResponse(response)
        } catch {
            return fallbackPatternExplanation(for: correlation)
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
