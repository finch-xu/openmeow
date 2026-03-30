import Foundation

nonisolated struct VoiceInfo: Codable, Sendable {
    let id: String
    let name: String
    let language: String
    let gender: String?
}

nonisolated protocol TTSProvider: Sendable {
    var providerID: String { get }
    var displayName: String { get }
    var supportedModels: [String] { get }

    func generate(text: String, voice: String, speed: Float, model: String) async throws -> AudioBuffer
    func listVoices(for model: String) -> [VoiceInfo]

    /// Explicitly release C/GPU/CoreML resources. Called when the provider is unregistered.
    func cleanup() async
}

extension TTSProvider {
    func cleanup() async {}
}
