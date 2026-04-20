import Foundation

#if SHERPA_ONNX_AVAILABLE
/// Serializes all C API calls through a single actor to prevent concurrent access to the recognizer pointer.
private actor SherpaOnnxASRActor {
    private let recognizerPointer: OpaquePointer

    init(recognizerPointer: OpaquePointer) {
        self.recognizerPointer = recognizerPointer
    }

    func transcribe(audio: [Float], sampleRate: Int, language: String?) throws -> (text: String, lang: String?) {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizerPointer) else {
            throw SherpaOnnxError.transcriptionFailed
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), audio, Int32(audio.count))
        SherpaOnnxDecodeOfflineStream(recognizerPointer, stream)

        guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw SherpaOnnxError.transcriptionFailed
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(resultPtr) }

        let text = resultPtr.pointee.text != nil ? String(cString: resultPtr.pointee.text) : ""
        let lang = resultPtr.pointee.lang != nil ? String(cString: resultPtr.pointee.lang) : language
        return (text, lang)
    }

    func destroy() {
        SherpaOnnxDestroyOfflineRecognizer(recognizerPointer)
    }
}
#endif

nonisolated final class SherpaOnnxASR: @unchecked Sendable {
    let providerID = "sherpa-onnx-asr"
    let displayName = "Sherpa-ONNX ASR (Local CPU)"
    let supportedModels: [String]

    private let modelPath: String
    private let asrFamily: String
    private let asrLanguages: [String]

    #if SHERPA_ONNX_AVAILABLE
    private let asrActor: SherpaOnnxASRActor
    #endif

    /// Initialize from a registry entry's config.
    init(modelPath: String, modelID: String, family: String,
         config: ModelConfig, languages: [String] = []) throws {
        self.modelPath = modelPath
        self.supportedModels = [modelID]
        self.asrFamily = family
        self.asrLanguages = languages

        #if SHERPA_ONNX_AVAILABLE
        var recognizerConfig = SherpaOnnxOfflineRecognizerConfig()
        recognizerConfig.feat_config.sample_rate = Int32(config.asrSampleRate ?? 16000)
        recognizerConfig.feat_config.feature_dim = Int32(config.featureDim ?? 80)
        let threads = Int32(config.numThreads ?? 4)
        recognizerConfig.model_config.num_threads = threads

        // CStringScope keeps strdup'd C strings alive until after SherpaOnnxCreateOfflineRecognizer copies them.
        let cStrings = CStringScope()

        recognizerConfig.decoding_method = cStrings.cString(config.decodingMethod ?? "greedy_search")

        func resolve(_ relative: String?) -> String {
            resolveModelPath(modelPath, relative)
        }

        let asrType = config.asrModelType ?? family

        switch asrType {
        case "sense_voice", "sensevoice":
            let modelFile = resolve(config.modelFile)
            guard FileManager.default.fileExists(atPath: modelFile) else {
                throw SherpaOnnxError.modelNotFound(modelFile)
            }
            recognizerConfig.model_config.sense_voice.model = cStrings.cString(modelFile)
            recognizerConfig.model_config.sense_voice.language = cStrings.cString("")
            recognizerConfig.model_config.sense_voice.use_itn = 1
            recognizerConfig.model_config.tokens = cStrings.cString(resolve(config.tokensFile))

        case "whisper":
            recognizerConfig.model_config.whisper.encoder = cStrings.cString(resolve(config.encoder))
            recognizerConfig.model_config.whisper.decoder = cStrings.cString(resolve(config.decoder))
            recognizerConfig.model_config.tokens = cStrings.cString(resolve(config.tokensFile))

        case "paraformer":
            recognizerConfig.model_config.paraformer.model = cStrings.cString(resolve(config.modelFile ?? config.encoder ?? ""))
            recognizerConfig.model_config.tokens = cStrings.cString(resolve(config.tokensFile))

        case "ctc", "fire-red-asr":
            let modelFile = resolve(config.modelFile)
            recognizerConfig.model_config.fire_red_asr_ctc.model = cStrings.cString(modelFile)
            recognizerConfig.model_config.tokens = cStrings.cString(resolve(config.tokensFile))

        default:
            throw SherpaOnnxError.initializationFailed("Unknown ASR model type: \(asrType)")
        }

        guard let ptr = SherpaOnnxCreateOfflineRecognizer(&recognizerConfig) else {
            throw SherpaOnnxError.initializationFailed("SherpaOnnxCreateOfflineRecognizer returned nil for \(modelID)")
        }
        self.asrActor = SherpaOnnxASRActor(recognizerPointer: ptr)
        // cStrings deallocates here — safe because SherpaOnnxCreateOfflineRecognizer copies all strings internally
        #endif
    }
}

nonisolated extension SherpaOnnxASR: ASRProvider {

    func cleanup() async {
        #if SHERPA_ONNX_AVAILABLE
        await asrActor.destroy()
        #endif
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        model: String
    ) async throws -> ASRResult {
        #if SHERPA_ONNX_AVAILABLE
        let result = try await asrActor.transcribe(audio: audio, sampleRate: sampleRate, language: language)
        return ASRResult(text: result.text)
        #else
        let duration = Double(audio.count) / Double(sampleRate)
        return ASRResult(text: "[Placeholder] Transcription of \(String(format: "%.1f", duration))s audio")
        #endif
    }

    func supportedLanguages(for model: String) -> [String] {
        asrLanguages
    }
}

// toCPointer and resolveModelPath are in SherpaOnnxHelpers.swift
