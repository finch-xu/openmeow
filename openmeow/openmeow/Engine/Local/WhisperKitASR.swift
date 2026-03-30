import Foundation
import OSLog

#if WHISPERKIT_AVAILABLE
import WhisperKit
#endif

#if WHISPERKIT_AVAILABLE
/// Serializes WhisperKit access to prevent concurrent CoreML inference on the same model.
private actor WhisperKitASRActor {
    // nonisolated(unsafe) because WhisperKit is not Sendable, but the actor guarantees serial access.
    nonisolated(unsafe) private var whisperKit: WhisperKit?

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    func transcribe(audioArray: [Float], decodeOptions: DecodingOptions) async throws -> [TranscriptionResult] {
        guard let kit = whisperKit else { throw WhisperKitError.transcriptionFailed("Model already released") }
        nonisolated(unsafe) let wk = kit
        return try await wk.transcribe(audioArray: audioArray, decodeOptions: decodeOptions)
    }

    func cleanup() {
        whisperKit = nil
    }
}
#endif

nonisolated final class WhisperKitASR: @unchecked Sendable {
    let providerID = "whisperkit-asr"
    let displayName = "WhisperKit ASR (CoreML)"
    let supportedModels: [String]

    private let asrLanguages: [String]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "WhisperKitASR")

    #if WHISPERKIT_AVAILABLE
    private let asrActor: WhisperKitASRActor
    #endif

    init(modelID: String, modelPath: String, variant: String, languages: [String] = []) async throws {
        self.supportedModels = [modelID]
        self.asrLanguages = languages

        #if WHISPERKIT_AVAILABLE
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: modelPath,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        self.asrActor = WhisperKitASRActor(whisperKit: try await WhisperKit(config))
        #endif
    }

    static func downloadModel(variant: String, to directory: URL) async throws -> URL {
        #if WHISPERKIT_AVAILABLE
        return try await WhisperKit.download(variant: variant, downloadBase: directory)
        #else
        throw WhisperKitError.modelNotAvailable("WHISPERKIT_AVAILABLE not set")
        #endif
    }
}

nonisolated extension WhisperKitASR: ASRProvider {

    func cleanup() async {
        #if WHISPERKIT_AVAILABLE
        await asrActor.cleanup()
        #endif
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        model: String
    ) async throws -> ASRResult {
        #if WHISPERKIT_AVAILABLE
        var options = DecodingOptions()
        options.language = language

        let results = try await asrActor.transcribe(audioArray: audio, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let detectedLang = results.first?.language ?? language
        let duration = Double(audio.count) / Double(sampleRate)

        let segments: [ASRSegment]? = results.first?.segments.isEmpty == false
            ? results.first?.segments.enumerated().map { i, seg in
                ASRSegment(id: i, start: Double(seg.start), end: Double(seg.end), text: seg.text)
            }
            : nil

        return ASRResult(text: text, language: detectedLang, duration: duration, segments: segments)
        #else
        let duration = Double(audio.count) / Double(sampleRate)
        return ASRResult(
            text: "[Placeholder] Transcription of \(String(format: "%.1f", duration))s audio",
            language: language ?? "en",
            duration: duration,
            segments: nil
        )
        #endif
    }

    func supportedLanguages(for model: String) -> [String] {
        asrLanguages
    }
}
