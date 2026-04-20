import Foundation
import OSLog

#if SPEECH_SWIFT_AVAILABLE
import Qwen3TTS
import MLX
#endif

// MARK: - Errors

nonisolated enum SpeechSwiftError: Error, LocalizedError {
    case modelNotAvailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let msg): "speech-swift model not available: \(msg)"
        case .generationFailed(let msg): "TTS generation failed: \(msg)"
        }
    }
}

// MARK: - Actor-isolated model wrapper (Qwen3TTSModel is NOT thread-safe)

#if SPEECH_SWIFT_AVAILABLE
private actor TTSModelActor {
    private var model: Qwen3TTSModel?

    init(model: sending Qwen3TTSModel) {
        self.model = model
    }

    func synthesize(text: String, language: String, speaker: String?) throws -> [Float] {
        guard let model else { throw SpeechSwiftError.generationFailed("Model already released") }
        let result = model.synthesize(text: text, language: language, speaker: speaker)
        Memory.clearCache()
        return result
    }

    func cleanup() {
        model = nil
        MLX.GPU.clearCache()
    }
}
#endif

// MARK: - SpeechSwiftTTS Provider

nonisolated final class SpeechSwiftTTS: @unchecked Sendable {
    let providerID = "speech-swift-tts"
    let displayName = "Qwen3-TTS (MLX)"
    let supportedModels: [String]

    private let voiceList: [VoiceInfo]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SpeechSwiftTTS")

    #if SPEECH_SWIFT_AVAILABLE
    private let modelActor: TTSModelActor
    #endif

    #if SPEECH_SWIFT_AVAILABLE
    init(modelID: String, model: sending Qwen3TTSModel, voices: [VoiceInfo] = []) {
        self.supportedModels = [modelID]
        self.voiceList = voices
        self.modelActor = TTSModelActor(model: model)
    }
    #else
    init(modelID: String, voices: [VoiceInfo] = []) {
        self.supportedModels = [modelID]
        self.voiceList = voices
    }
    #endif

    /// Load model via speech-swift's fromPretrained (handles download + init).
    /// progressHandler receives (fraction 0..1, status message).
    /// Pass `cacheDir` to control where weights are stored; pass `offlineMode: true`
    /// when re-loading already-downloaded files to skip network checks.
    static func loadModel(
        hfModelID: String,
        cacheDir: URL? = nil,
        offlineMode: Bool = false,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Any {
        #if SPEECH_SWIFT_AVAILABLE
        return try await Qwen3TTSModel.fromPretrained(
            modelId: hfModelID,
            cacheDir: cacheDir,
            offlineMode: offlineMode,
            progressHandler: progressHandler
        )
        #else
        throw SpeechSwiftError.modelNotAvailable("SPEECH_SWIFT_AVAILABLE not set")
        #endif
    }
}

// MARK: - TTSProvider Conformance

nonisolated extension SpeechSwiftTTS: TTSProvider {

    func cleanup() async {
        #if SPEECH_SWIFT_AVAILABLE
        await modelActor.cleanup()
        #endif
    }

    func generate(text: String, voice: String, speed: Float, model: String) async throws -> AudioBuffer {
        #if SPEECH_SWIFT_AVAILABLE
        let (language, speaker) = resolveVoice(voice)
        logger.debug("Generating TTS: voice=\(voice), language=\(language), speaker=\(speaker ?? "nil"), text length=\(text.count)")
        let samples = try await modelActor.synthesize(text: text, language: language, speaker: speaker)
        guard !samples.isEmpty else {
            throw SpeechSwiftError.generationFailed("Empty audio output")
        }
        return AudioBuffer(samples: samples, sampleRate: 24000)
        #else
        let numSamples = Int(Float(text.count) * 0.06 * 24000)
        return AudioBuffer(samples: [Float](repeating: 0, count: max(numSamples, 1)), sampleRate: 24000)
        #endif
    }

    func listVoices(for model: String) -> [VoiceInfo] {
        voiceList
    }

    /// Map voice ID/name to (language, speaker) for speech-swift API.
    private func resolveVoice(_ voice: String) -> (language: String, speaker: String?) {
        let info = voiceList.first(where: { $0.id == voice })
            ?? voiceList.first(where: { $0.name.lowercased() == voice.lowercased() })
        let language = info?.language ?? "english"
        let speaker = info?.name
        return (language, speaker)
    }
}
