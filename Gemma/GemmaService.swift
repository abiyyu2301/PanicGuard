import Foundation

// MARK: - Gemma Service (DEPRECATED — redirects to GemmaServiceLiteRT)
/// This class is deprecated. All inference now routes through `GemmaServiceLiteRT`.
/// Kept as a stub to avoid breaking any source-level references that may survive refactoring.
/// Remove once all call sites are confirmed on `GemmaServiceLiteRT.shared`.
final class GemmaService: ObservableObject {
    static let shared = GemmaService()

    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastDecision: InterventionType?
    @Published var lastError: Error?

    private let maxTokens: Int = 256
    private let temperature: Float = 0.3
    private let topk: Int = 40

    /// Proxies to GemmaServiceLiteRT.shared for all actual inference.
    /// Falls back to simulation mode when no `.litertlm` model is bundled.
    func loadModel() async {
        await GemmaServiceLiteRT.shared.loadModel()
    }

    /// Synchronous simulation stub — delegates to LiteRT backend.
    func generateResponse(prompt: String) throws -> String {
        return try GemmaServiceLiteRT.shared.generateResponseSync(prompt: prompt)
    }

    /// Async inference stub — delegates to LiteRT backend.
    func generateResponse(prompt: String) async throws -> String {
        return try await GemmaServiceLiteRT.shared.generateResponse(prompt: prompt)
    }

    /// Build a panic intervention decision from current biometrics + journal context.
    /// Routes to GemmaServiceLiteRT.makeDecision().
    func makeDecision(heartRate: Double, hrv: Double, journalContext: String) async -> InterventionType {
        return await GemmaServiceLiteRT.shared.makeDecision(
            heartRate: heartRate,
            hrv: hrv,
            journalContext: journalContext
        )
    }

    /// Returns true if the LiteRT model is loaded and ready.
    var isReady: Bool {
        return GemmaServiceLiteRT.shared.isModelLoaded
    }
}
