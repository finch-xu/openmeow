import Foundation

/// Cloud TTS provider for Xiaomi MiMo's chat completions-based TTS API.
/// Uses `/v1/chat/completions` with an `audio` field, returning base64-encoded audio in JSON.
nonisolated final class MiMoCloudTTS: TTSProvider, @unchecked Sendable {
    let providerID = "mimo-cloud-tts"
    let displayName = "MiMo TTS (Cloud)"
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

        let urlString = "\(endpoint)/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw CloudTTSError.invalidEndpoint(urlString)
        }

        // MiMo format: text to synthesize goes in assistant role
        let body: [String: Any] = [
            "model": cloudModel,
            "messages": [
                ["role": "assistant", "content": text]
            ],
            "audio": [
                "format": "wav",
                "voice": voice
            ]
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

        // Parse JSON response: choices[0].message.audio.data (base64)
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CloudTTSError.invalidResponse("Response is not a JSON object")
            }
            json = parsed
        } catch let error as CloudTTSError {
            throw error
        } catch {
            throw CloudTTSError.invalidResponse("JSON parsing failed: \(error.localizedDescription)")
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let audio = message["audio"] as? [String: Any],
              let audioDataString = audio["data"] as? String else {
            throw CloudTTSError.invalidResponse("Missing choices[0].message.audio.data")
        }

        guard let audioData = Data(base64Encoded: audioDataString) else {
            throw CloudTTSError.audioDecodingFailed("Invalid base64 audio data")
        }

        do {
            return try AudioDecoder.decode(audioData)
        } catch {
            throw CloudTTSError.audioDecodingFailed(error.localizedDescription)
        }
    }

    func listVoices(for model: String) -> [VoiceInfo] {
        voiceList
    }

    func cleanup() async {}
}
