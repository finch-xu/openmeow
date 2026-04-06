import Foundation

/// Cloud TTS provider for the standard OpenAI `/v1/audio/speech` API format.
/// Compatible with OpenAI, Azure OpenAI, Fish Audio, and other services using this endpoint.
nonisolated final class OpenAICloudTTS: TTSProvider, @unchecked Sendable {
    let providerID = "openai-cloud-tts"
    let displayName = "OpenAI TTS (Cloud)"
    let supportedModels: [String]

    private let endpoint: String
    private let cloudModel: String
    private let apiKeySettingsKey: String
    private let authHeader: String
    private let authPrefix: String
    private let voiceList: [VoiceInfo]

    init(modelID: String, endpoint: String, cloudModel: String,
         apiKeySettingsKey: String, authHeader: String, authPrefix: String,
         voices: [VoiceInfo]) {
        self.endpoint = endpoint
        self.cloudModel = cloudModel
        self.apiKeySettingsKey = apiKeySettingsKey
        self.authHeader = authHeader
        self.authPrefix = authPrefix
        self.supportedModels = [modelID]
        self.voiceList = voices
    }

    func generate(text: String, voice: String, speed: Float, model: String) async throws -> AudioBuffer {
        let apiKey = UserDefaults.standard.string(forKey: apiKeySettingsKey) ?? ""
        guard !apiKey.isEmpty else { throw CloudTTSError.apiKeyNotConfigured }

        let urlString = "\(endpoint)/v1/audio/speech"
        guard let url = URL(string: urlString) else {
            throw CloudTTSError.invalidEndpoint(urlString)
        }

        // Build request body: standard OpenAI audio speech format
        let body: [String: Any] = [
            "model": cloudModel,
            "input": text,
            "voice": voice,
            "speed": speed,
            "response_format": "wav"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(authPrefix)\(apiKey)", forHTTPHeaderField: authHeader)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudTTSError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTTSError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudTTSError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        // Response is raw audio bytes — decode to AudioBuffer
        do {
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            return try AudioDecoder.decode(data, contentTypeHint: contentType)
        } catch {
            throw CloudTTSError.audioDecodingFailed(error.localizedDescription)
        }
    }

    func listVoices(for model: String) -> [VoiceInfo] {
        voiceList
    }

    func cleanup() async {}
}
