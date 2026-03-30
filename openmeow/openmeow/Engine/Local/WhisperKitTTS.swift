import Foundation
import OSLog

#if WHISPERKIT_AVAILABLE
import TTSKit
#endif

nonisolated enum WhisperKitError: Error, CustomStringConvertible {
    case modelNotAvailable(String)
    case generationFailed(String)
    case transcriptionFailed(String)
    case downloadFailed(String)

    var description: String {
        switch self {
        case .modelNotAvailable(let msg): "Model not available: \(msg)"
        case .generationFailed(let msg): "TTS generation failed: \(msg)"
        case .transcriptionFailed(let msg): "ASR transcription failed: \(msg)"
        case .downloadFailed(let msg): "Download failed: \(msg)"
        }
    }
}

#if WHISPERKIT_AVAILABLE
/// Serializes TTSKit access to prevent concurrent CoreML inference on the same model.
private actor TTSKitActor {
    // nonisolated(unsafe) because TTSKit is not Sendable, but the actor guarantees serial access.
    nonisolated(unsafe) private var ttsKit: TTSKit?

    init(ttsKit: TTSKit) {
        self.ttsKit = ttsKit
    }

    func generate(text: String, voice: String) async throws -> (audio: [Float], sampleRate: Int) {
        guard let kit = ttsKit else { throw WhisperKitError.generationFailed("Model already released") }
        nonisolated(unsafe) let tk = kit
        let result = try await tk.generate(text: text, voice: voice)
        return (result.audio, result.sampleRate)
    }

    func cleanup() {
        ttsKit = nil
    }
}
#endif

nonisolated final class WhisperKitTTS: @unchecked Sendable {
    let providerID = "whisperkit-tts"
    let displayName = "TTSKit (CoreML)"
    let supportedModels: [String]

    private let voiceList: [VoiceInfo]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "WhisperKitTTS")

    #if WHISPERKIT_AVAILABLE
    private let ttsKitActor: TTSKitActor
    #endif

    init(modelID: String, modelPath: String, variant: String, voices: [VoiceInfo] = []) async throws {
        self.supportedModels = [modelID]
        self.voiceList = voices

        #if WHISPERKIT_AVAILABLE
        let ttsVariant: TTSModelVariant = variant == "qwen3TTS_1_7b" ? .qwen3TTS_1_7b : .qwen3TTS_0_6b
        let config = TTSKitConfig(
            model: ttsVariant,
            modelFolder: URL(fileURLWithPath: modelPath),
            verbose: false,
            download: false,
            prewarm: true,
            load: true
        )
        self.ttsKitActor = TTSKitActor(ttsKit: try await TTSKit(config))
        #endif
    }

    static func downloadModel(variant: String, to directory: URL) async throws -> URL {
        #if WHISPERKIT_AVAILABLE
        let ttsVariant: TTSModelVariant = variant == "qwen3TTS_1_7b" ? .qwen3TTS_1_7b : .qwen3TTS_0_6b
        return try await TTSKit.download(variant: ttsVariant, downloadBase: directory)
        #else
        throw WhisperKitError.modelNotAvailable("WHISPERKIT_AVAILABLE not set")
        #endif
    }
}

nonisolated extension WhisperKitTTS: TTSProvider {

    func cleanup() async {
        #if WHISPERKIT_AVAILABLE
        await ttsKitActor.cleanup()
        #endif
    }

    func generate(text: String, voice: String, speed: Float, model: String) async throws -> AudioBuffer {
        #if WHISPERKIT_AVAILABLE
        let voiceName = normalizeVoiceName(voice)
        let result = try await ttsKitActor.generate(text: text, voice: voiceName)
        return AudioBuffer(samples: result.audio, sampleRate: result.sampleRate)
        #else
        let numSamples = Int(Float(text.count) * 0.06 * 24000)
        let samples = [Float](repeating: 0, count: max(numSamples, 1))
        return AudioBuffer(samples: samples, sampleRate: 24000)
        #endif
    }

    func listVoices(for model: String) -> [VoiceInfo] {
        voiceList
    }

    private func normalizeVoiceName(_ voice: String) -> String {
        // Convert voice IDs like "ono_anna" to TTSKit format "ono anna"
        // and "uncle_fu" to "uncle fu"
        voice.replacingOccurrences(of: "_", with: " ")
    }
}
