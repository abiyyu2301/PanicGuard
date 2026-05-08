import Foundation

// MARK: - LiteRT Swift-C Interop Layer
/// Swift wrapper around the LiteRT-LM C API (`libLiteRt.dylib`).
/// Provides a Swift-native interface for model loading, inference, and streaming
/// using the `LiteRtLmEngine` / `LiteRtLmSession` C API surface.

final class LiteRTModel {
    // MARK: - C API Handles

    /// Opaque pointer to the LiteRT engine. Owned — must call `litert_lm_engine_delete`.
    private var engine: OpaquePointer?

    /// Opaque pointer to the current session. Owned — must call `litert_lm_session_delete`.
    private var session: OpaquePointer?

    /// Session config used for the current session.
    private var sessionConfig: OpaquePointer?

    // MARK: - Configuration

    let maxOutputTokens: Int
    let temperature: Float
    let topK: Int
    let topP: Float

    /// Backend string passed to `litert_lm_engine_settings_create`.
    /// "cpu", "gpu", or "metal" on iOS.
    let backend: String

    // MARK: - State

    private(set) var isModelLoaded: Bool = false
    private(set) var isSessionActive: Bool = false
    private let inferenceQueue = DispatchQueue(label: "com.panicguard.litert.inference", qos: .userInitiated)

    // MARK: - Initialization

    /// Creates a LiteRT model wrapper. Does not load the model yet — call `loadModel()`.
    init(
        maxOutputTokens: Int = 256,
        temperature: Float = 0.3,
        topK: Int = 40,
        topP: Float = 0.95,
        backend: String = "metal"
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.backend = backend
    }

    deinit {
        destroySession()
        destroyEngine()
    }

    // MARK: - Model Loading

    /// Loads the LiteRT engine from the `.litertlm` model file at `modelPath`.
    /// - Parameter modelPath: Absolute path to the `.litertlm` model bundle resource.
    /// - Throws: `LiteRTError` on load failure.
    func loadModel(from modelPath: String) throws {
        guard !isModelLoaded else { return }

        var settings: OpaquePointer?
        settings = litert_lm_engine_settings_create(
            modelPath,
            backend,
            nil,  // vision_backend_str
            nil   // audio_backend_str
        )
        guard let engineSettings = settings else {
            throw LiteRTError.settingsCreationFailed
        }

        litert_lm_engine_settings_set_max_num_tokens(engineSettings, maxOutputTokens)
        // Enable parallel file section loading for faster startup on iOS
        litert_lm_engine_settings_set_parallel_file_section_loading(engineSettings, true)

        engine = litert_lm_engine_create(engineSettings)
        litert_lm_engine_settings_delete(engineSettings)

        guard let engine = engine else {
            throw LiteRTError.engineCreationFailed
        }

        self.engine = engine
        isModelLoaded = true
        print("[LiteRTModel] Engine loaded successfully from \(modelPath)")
    }

    /// Checks whether a model file exists in the bundle.
    /// Returns the path if found, nil otherwise.
    static func modelPathInBundle(
        _ name: String = "gemma-4-E2B-it",
        extension ext: String = "litertlm"
    ) -> String? {
        Bundle.main.path(forResource: name, ofType: ext)
    }

    // MARK: - Session Management

    /// Creates a new inference session using the current engine.
    /// The previous session (if any) is destroyed first.
    /// - Throws: `LiteRTError` if engine is not loaded or session creation fails.
    func createSession() throws {
        guard let engine = engine else {
            throw LiteRTError.engineNotLoaded
        }

        destroySession()

        // Build session config with inference parameters
        let config = litert_lm_session_config_create()
        defer { litert_lm_session_config_delete(config) }

        litert_lm_session_config_set_max_output_tokens(config, maxOutputTokens)

        // Gemma models use their own prompt template internally.
        // Disable LiteRT's wrapper template so Gemma's built-in template is used.
        litert_lm_session_config_set_apply_prompt_template(config, false)

        // Set sampler parameters
        var samplerParams = LiteRtLmSamplerParams(
            type: topK > 0 ? Int32(kLiteRtLmSamplerTypeTopK.rawValue) : Int32(kLiteRtLmSamplerTypeTopP.rawValue),
            top_k: Int32(topK),
            top_p: topP,
            temperature: temperature,
            seed: 0
        )
        litert_lm_session_config_set_sampler_params(config, &samplerParams)

        sessionConfig = config
        session = litert_lm_engine_create_session(engine, config)
        guard let session = session else {
            throw LiteRTError.sessionCreationFailed
        }

        self.session = session
        isSessionActive = true
        print("[LiteRTModel] Session created (max_tokens=\(maxOutputTokens), temp=\(temperature), topK=\(topK))")
    }

    // MARK: - Inference (Blocking)

    /// Runs synchronous inference with the given prompt string.
    /// Internally creates a session if needed.
    /// - Parameter prompt: The full prompt string (including system prompt and user input).
    /// - Returns: The model's generated text response.
    /// - Throws: `LiteRTError` on prefill, decode, or response failure.
    func generateResponse(prompt: String) throws -> String {
        try ensureSessionReady()

        guard let session = session else {
            throw LiteRTError.sessionNotReady
        }

        // Build the input data struct for the C API
        var inputData = LiteRtLmInputData(
            type: kLiteRtLmInputDataTypeText,
            data: prompt,
            size: prompt.utf8.count
        )

        // Generate content (prefill + decode in one shot)
        let responses: UnsafeMutablePointer<litert_lm_responses_t>?
        withUnsafeMutablePointer(to: &inputData) { inputPtr in
            responses = litert_lm_session_generate_content(session, inputPtr, 1)
        }
        guard let responses else {
            throw LiteRTError.inferenceFailed("generate_content returned NULL")
        }
        defer { litert_lm_responses_delete(responses) }

        let numCandidates = litert_lm_responses_get_num_candidates(responses)
        guard numCandidates > 0 else {
            throw LiteRTError.inferenceFailed("no response candidates")
        }

        guard let responseText = litert_lm_responses_get_response_text_at(responses, 0) else {
            throw LiteRTError.inferenceFailed("response text at index 0 was NULL")
        }

        // The response string is owned by `responses` and valid until responses_delete.
        // Copy it to Swift memory before the defer block destroys it.
        let result = String(cString: responseText)
        return result
    }

    /// Runs inference asynchronously on the inference queue.
    func generateResponseAsync(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                do {
                    let result = try self.generateResponse(prompt: prompt)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Streaming Inference

    /// Runs streaming inference, yielding partial tokens as they're generated.
    /// - Parameter prompt: The full prompt string.
    /// - Returns: An `AsyncThrowingStream` yielding response chunks.
    func generateResponseStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            self.inferenceQueue.async {
                do {
                    // Ensure session is ready before streaming
                    try self.ensureSessionReady()

                    guard let session = self.session else {
                        continuation.finish(throwing: LiteRTError.sessionNotReady)
                        return
                    }

                    // Build input data
                    var inputData = LiteRtLmInputData(
                        type: kLiteRtLmInputDataTypeText,
                        data: prompt,
                        size: prompt.utf8.count
                    )

                    // State object shared between the C callback and this continuation
                    let state = StreamState()

                    // Wrap continuation in a class for Objective-C compatibility
                    let streamWrapper = StreamWrapper(continuation: continuation, state: state)

                    // Cast the Swift callback to the C function pointer type
                    let callback: LiteRtLmStreamCallback = { callbackData, chunk, isFinal, errorMsg in
                        guard let wrapper = callbackData else { return }
                        let w = Unmanaged<StreamWrapper>.fromOpaque(wrapper).takeUnretainedValue()
                        w.handleChunk(chunk: chunk, isFinal: isFinal, errorMsg: errorMsg)
                    }

                    let opaqueWrapper = Unmanaged.passUnretained(streamWrapper).toOpaque()

                    let status = withUnsafePointer(to: &inputData) { inputPtr in
                        litert_lm_session_generate_content_stream(session, inputPtr, 1, callback, opaqueWrapper)
                    }

                    if status != 0 {
                        continuation.finish(throwing: LiteRTError.streamingFailed(status))
                    }
                    // Note: completion is handled by the is_final=true callback

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Benchmarking

    /// Retrieves benchmark info from the current session.
    func getBenchmarkInfo() -> BenchmarkInfo? {
        guard let session = session else { return nil }
        guard let info = litert_lm_session_get_benchmark_info(session) else { return nil }
        defer { litert_lm_benchmark_info_delete(info) }

        return BenchmarkInfo(
            timeToFirstToken: litert_lm_benchmark_info_get_time_to_first_token(info),
            totalInitTime: litert_lm_benchmark_info_get_total_init_time_in_second(info),
            numPrefillTurns: litert_lm_benchmark_info_get_num_prefill_turns(info),
            numDecodeTurns: litert_lm_benchmark_info_get_num_decode_turns(info)
        )
    }

    // MARK: - Session Helpers

    private func ensureSessionReady() throws {
        if !isSessionActive || session == nil {
            try createSession()
        }
    }

    private func destroySession() {
        if let session = session {
            litert_lm_session_delete(session)
            self.session = nil
        }
        isSessionActive = false
    }

    private func destroyEngine() {
        destroySession()
        if let engine = engine {
            litert_lm_engine_delete(engine)
            self.engine = nil
        }
        isModelLoaded = false
    }
}

// MARK: - Error Types

enum LiteRTError: Error, LocalizedError {
    case engineNotLoaded
    case engineCreationFailed
    case settingsCreationFailed
    case sessionCreationFailed
    case sessionNotReady
    case inferenceFailed(String)
    case streamingFailed(Int32)
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .engineNotLoaded:    return "LiteRT engine not loaded. Call loadModel() first."
        case .engineCreationFailed: return "LiteRT engine creation failed."
        case .settingsCreationFailed: return "LiteRT engine settings creation failed."
        case .sessionCreationFailed:  return "LiteRT session creation failed."
        case .sessionNotReady:   return "LiteRT session is not ready."
        case .inferenceFailed(let msg): return "Inference failed: \(msg)"
        case .streamingFailed(let code): return "Streaming inference failed with code \(code)"
        case .modelNotFound:     return "Model file not found in bundle."
        }
    }
}

// MARK: - Benchmark Info

struct BenchmarkInfo {
    let timeToFirstToken: Double       // seconds
    let totalInitTime: Double          // seconds
    let numPrefillTurns: Int
    let numDecodeTurns: Int

    var summary: String {
        String(format: "TTFT: %.3fs | Init: %.2fs | Prefill turns: %d | Decode turns: %d",
               timeToFirstToken, totalInitTime, numPrefillTurns, numDecodeTurns)
    }
}

// MARK: - Streaming Support

/// Tracks accumulated streaming state to detect token boundaries.
private final class StreamState {
    var buffer: String = ""
}

/// Bridges the C streaming callback to Swift's AsyncStream continuation.
private final class StreamWrapper {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    let state: StreamState

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, state: StreamState) {
        self.continuation = continuation
        self.state = state
    }

    func handleChunk(chunk: UnsafePointer<CChar>?, isFinal: Bool, errorMsg: UnsafePointer<CChar>?) {
        // Check for errors first
        if let errorMsg = errorMsg {
            let msg = String(cString: errorMsg)
            if !msg.isEmpty {
                continuation.finish(throwing: LiteRTError.inferenceFailed("streaming error: \(msg)"))
                return
            }
        }

        // Deliver the chunk
        if let chunk = chunk {
            let text = String(cString: chunk)
            if !text.isEmpty {
                continuation.yield(text)
            }
        }

        // Final chunk — end the stream
        if isFinal {
            continuation.finish()
        }
    }
}
