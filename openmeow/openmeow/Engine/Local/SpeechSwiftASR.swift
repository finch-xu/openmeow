import Foundation
import OSLog

#if SPEECH_SWIFT_AVAILABLE
import Qwen3ASR
import MLX
#endif

// MARK: - Actor-isolated model wrapper (Qwen3ASRModel is NOT thread-safe)

#if SPEECH_SWIFT_AVAILABLE
private actor ASRModelActor {
    private var model: Qwen3ASRModel?

    init(model: sending Qwen3ASRModel) {
        self.model = model
    }

    func transcribe(audio: [Float], sampleRate: Int, language: String?) throws -> String {
        guard let model else { throw SpeechSwiftError.generationFailed("Model already released") }
        return model.transcribe(audio: audio, sampleRate: sampleRate, language: language)
    }

    func cleanup() {
        model = nil
        MLX.GPU.clearCache()
    }
}
#endif

// MARK: - SpeechSwiftASR Provider

nonisolated final class SpeechSwiftASR: @unchecked Sendable {
    let providerID = "speech-swift-asr"
    let displayName = "Qwen3-ASR (MLX)"
    let supportedModels: [String]

    private let asrLanguages: [String]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SpeechSwiftASR")

    #if SPEECH_SWIFT_AVAILABLE
    private let modelActor: ASRModelActor
    #endif

    #if SPEECH_SWIFT_AVAILABLE
    init(modelID: String, model: sending Qwen3ASRModel, languages: [String] = []) {
        self.supportedModels = [modelID]
        self.asrLanguages = languages
        self.modelActor = ASRModelActor(model: model)
    }
    #else
    init(modelID: String, languages: [String] = []) {
        self.supportedModels = [modelID]
        self.asrLanguages = languages
    }
    #endif

    /// Load model via speech-swift's fromPretrained (handles download + init).
    static func loadModel(
        hfModelID: String,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Any {
        #if SPEECH_SWIFT_AVAILABLE
        return try await Qwen3ASRModel.fromPretrained(
            modelId: hfModelID,
            progressHandler: progressHandler
        )
        #else
        throw SpeechSwiftError.modelNotAvailable("SPEECH_SWIFT_AVAILABLE not set")
        #endif
    }
}

// MARK: - ASRProvider Conformance

nonisolated extension SpeechSwiftASR: ASRProvider {

    func cleanup() async {
        #if SPEECH_SWIFT_AVAILABLE
        await modelActor.cleanup()
        #endif
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        model: String
    ) async throws -> ASRResult {
        #if SPEECH_SWIFT_AVAILABLE
        logger.debug("Transcribing: \(audio.count) samples at \(sampleRate)Hz, language=\(language ?? "auto")")
        let text = try await modelActor.transcribe(
            audio: audio, sampleRate: sampleRate, language: language
        )
        return ASRResult(text: text)
        #else
        return ASRResult(text: "[speech-swift not available]")
        #endif
    }

    func supportedLanguages(for model: String) -> [String] {
        asrLanguages
    }
}
