import Foundation

nonisolated enum ASRResponseFormat: String, Codable, Sendable {
    case json, text, srt, verbose_json, vtt
}

nonisolated struct ASRSegment: Codable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

nonisolated struct ASRResult: Codable, Sendable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [ASRSegment]?
}

nonisolated protocol ASRProvider: Sendable {
    var providerID: String { get }
    var displayName: String { get }
    var supportedModels: [String] { get }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        model: String
    ) async throws -> ASRResult

    func supportedLanguages(for model: String) -> [String]

    /// Explicitly release C/GPU/CoreML resources. Called when the provider is unregistered.
    func cleanup() async
}

extension ASRProvider {
    func cleanup() async {}
}
