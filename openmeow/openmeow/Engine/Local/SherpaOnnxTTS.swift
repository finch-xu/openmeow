import Foundation

nonisolated enum SherpaOnnxError: Error, CustomStringConvertible {
    case modelNotFound(String)
    case initializationFailed(String)
    case generationFailed
    case transcriptionFailed

    var description: String {
        switch self {
        case .modelNotFound(let path): "Model not found at: \(path)"
        case .initializationFailed(let msg): "Initialization failed: \(msg)"
        case .generationFailed: "TTS generation failed"
        case .transcriptionFailed: "ASR transcription failed"
        }
    }
}

#if SHERPA_ONNX_AVAILABLE
/// Serializes all C API calls through a single actor to prevent concurrent access to the C pointer.
private actor SherpaOnnxTTSActor {
    private let ttsPointer: OpaquePointer

    init(ttsPointer: OpaquePointer) {
        self.ttsPointer = ttsPointer
    }

    func generate(text: String, sid: Int32, speed: Float) throws -> (samples: [Float], sampleRate: Int) {
        var genConfig = SherpaOnnxGenerationConfig()
        genConfig.speed = speed
        genConfig.sid = sid

        guard let audioPtr = SherpaOnnxOfflineTtsGenerateWithConfig(
            ttsPointer, toCPointer(text), &genConfig, nil, nil
        ) else {
            throw SherpaOnnxError.generationFailed
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audioPtr) }

        let count = Int(audioPtr.pointee.n)
        let sr = Int(audioPtr.pointee.sample_rate)
        let samples: [Float]
        if let p = audioPtr.pointee.samples {
            samples = Array(UnsafeBufferPointer(start: p, count: count))
        } else {
            samples = []
        }
        return (samples, sr)
    }

    func destroy() {
        SherpaOnnxDestroyOfflineTts(ttsPointer)
    }
}
#endif

nonisolated final class SherpaOnnxTTS: @unchecked Sendable {
    let providerID = "sherpa-onnx"
    let displayName = "Sherpa-ONNX (Local CPU)"
    let supportedModels: [String]

    private let modelPath: String
    private let modelFamily: ModelFamily
    private let outputSampleRate: Int
    private let voiceList: [VoiceInfo]

    #if SHERPA_ONNX_AVAILABLE
    private let ttsActor: SherpaOnnxTTSActor
    #endif

    enum ModelFamily: String, Sendable {
        case kokoro, piper, matcha, kitten, melo
    }

    /// Initialize from a registry entry's config.
    init(modelPath: String, modelID: String, family: ModelFamily,
         config: ModelConfig, sampleRate: Int = 24000, voices: [VoiceInfo] = []) throws {
        self.modelPath = modelPath
        self.modelFamily = family
        self.supportedModels = [modelID]
        self.outputSampleRate = sampleRate
        self.voiceList = voices

        #if SHERPA_ONNX_AVAILABLE
        var ttsConfig = SherpaOnnxOfflineTtsConfig()
        let threads = Int32(config.numThreads ?? 4)

        // CStringScope keeps strdup'd C strings alive until after SherpaOnnxCreateOfflineTts copies them.
        let cStrings = CStringScope()

        // Resolve relative path; if resolved path doesn't exist, fallback to modelPath itself
        // (handles Xcode bundle flattening where espeak-ng-data/ is merged into Resources root)
        func resolve(_ relative: String?) -> String {
            let resolved = resolveModelPath(modelPath, relative)
            if !resolved.isEmpty && !FileManager.default.fileExists(atPath: resolved) {
                // Try the file directly in modelPath (flattened bundle)
                if let filename = relative?.components(separatedBy: "/").last,
                   FileManager.default.fileExists(atPath: resolveModelPath(modelPath, filename)) {
                    return resolveModelPath(modelPath, filename)
                }
            }
            return resolved
        }

        func resolveDir(_ relative: String?) -> String {
            let resolved = resolveModelPath(modelPath, relative)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
                return resolved
            }
            // Flattened bundle: data_dir content is in modelPath itself
            return modelPath
        }

        switch family {
        case .kokoro:
            let modelFile = resolve(config.modelFile)
            guard FileManager.default.fileExists(atPath: modelFile) else {
                throw SherpaOnnxError.modelNotFound(modelFile)
            }
            ttsConfig.model.kokoro.model = cStrings.cString(modelFile)
            ttsConfig.model.kokoro.voices = cStrings.cString(resolve(config.voicesFile))
            ttsConfig.model.kokoro.tokens = cStrings.cString(resolve(config.tokensFile))
            ttsConfig.model.kokoro.data_dir = cStrings.cString(resolveDir(config.dataDir))
            if let lexicon = config.lexicon {
                ttsConfig.model.kokoro.lexicon = cStrings.cString(resolve(lexicon))
            }
            if let dictDir = config.dictDir {
                ttsConfig.model.kokoro.dict_dir = cStrings.cString(resolveDir(dictDir))
            }
            ttsConfig.model.num_threads = threads

        case .piper, .melo:
            let modelFile = resolve(config.modelFile)
            ttsConfig.model.vits.model = cStrings.cString(modelFile)
            ttsConfig.model.vits.tokens = cStrings.cString(resolve(config.tokensFile))
            if config.dataDir != nil {
                ttsConfig.model.vits.data_dir = cStrings.cString(resolveDir(config.dataDir))
            }
            if let lexicon = config.lexicon {
                ttsConfig.model.vits.lexicon = cStrings.cString(resolve(lexicon))
            }
            if let dictDir = config.dictDir {
                ttsConfig.model.vits.dict_dir = cStrings.cString(resolveDir(dictDir))
            }
            ttsConfig.model.num_threads = threads

        case .kitten:
            let modelFile = resolve(config.modelFile)
            guard FileManager.default.fileExists(atPath: modelFile) else {
                throw SherpaOnnxError.modelNotFound(modelFile)
            }
            ttsConfig.model.kitten.model = cStrings.cString(modelFile)
            ttsConfig.model.kitten.voices = cStrings.cString(resolve(config.voicesFile))
            ttsConfig.model.kitten.tokens = cStrings.cString(resolve(config.tokensFile))
            ttsConfig.model.kitten.data_dir = cStrings.cString(resolveDir(config.dataDir))
            ttsConfig.model.num_threads = threads

        case .matcha:
            ttsConfig.model.matcha.acoustic_model = cStrings.cString(resolve(config.acousticModel))
            ttsConfig.model.matcha.vocoder = cStrings.cString(resolve(config.vocoder))
            ttsConfig.model.matcha.tokens = cStrings.cString(resolve(config.tokensFile))
            if config.dataDir != nil {
                ttsConfig.model.matcha.data_dir = cStrings.cString(resolveDir(config.dataDir))
            }
            if let lexicon = config.lexicon {
                ttsConfig.model.matcha.lexicon = cStrings.cString(resolve(lexicon))
            }
            if let dictDir = config.dictDir {
                ttsConfig.model.matcha.dict_dir = cStrings.cString(resolveDir(dictDir))
            }
            ttsConfig.model.num_threads = threads
        }

        guard let ptr = SherpaOnnxCreateOfflineTts(&ttsConfig) else {
            throw SherpaOnnxError.initializationFailed("SherpaOnnxCreateOfflineTts returned nil for \(modelID)")
        }
        self.ttsActor = SherpaOnnxTTSActor(ttsPointer: ptr)
        // cStrings deallocates here — safe because SherpaOnnxCreateOfflineTts copies all strings internally
        #endif
    }
}

nonisolated extension SherpaOnnxTTS: TTSProvider {

    func cleanup() async {
        #if SHERPA_ONNX_AVAILABLE
        await ttsActor.destroy()
        #endif
    }

    func generate(text: String, voice: String, speed: Float, model: String) async throws -> AudioBuffer {
        #if SHERPA_ONNX_AVAILABLE
        let sid = Int32(voiceNameToSpeakerID(voice))
        let result = try await ttsActor.generate(text: text, sid: sid, speed: speed)
        return AudioBuffer(samples: result.samples, sampleRate: result.sampleRate)
        #else
        let duration: Float = max(0.5, Float(text.count) * 0.06)
        let numSamples = Int(duration * Float(outputSampleRate))
        let frequency: Float = 440.0
        var samples = [Float](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            let t = Float(i) / Float(outputSampleRate)
            samples[i] = 0.3 * sin(2.0 * .pi * frequency * t * speed)
        }
        return AudioBuffer(samples: samples, sampleRate: outputSampleRate)
        #endif
    }

    func listVoices(for model: String) -> [VoiceInfo] {
        voiceList
    }

    private func voiceNameToSpeakerID(_ voice: String) -> Int {
        voiceList.firstIndex(where: { $0.id == voice }) ?? 0
    }
}

// toCPointer and resolveModelPath are in SherpaOnnxHelpers.swift
