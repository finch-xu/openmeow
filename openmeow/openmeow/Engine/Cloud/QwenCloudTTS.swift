import Foundation

/// Cloud TTS provider for Alibaba Cloud DashScope's Qwen3 TTS API.
/// Uses the multimodal generation endpoint, returning a WAV URL in the JSON response.
nonisolated final class QwenCloudTTS: TTSProvider, @unchecked Sendable {
    let providerID = "qwen-cloud-tts"
    let displayName = "Qwen TTS (Cloud)"
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

        let urlString = "\(endpoint)/api/v1/services/aigc/multimodal-generation/generation"
        guard let url = URL(string: urlString) else {
            throw CloudTTSError.invalidEndpoint(urlString)
        }

        // DashScope multimodal generation format
        let body: [String: Any] = [
            "model": cloudModel,
            "input": [
                "text": text,
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

        // Parse JSON response: output.audio.url
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

        guard let output = json["output"] as? [String: Any],
              let audio = output["audio"] as? [String: Any],
              let audioURLString = audio["url"] as? String,
              let audioURL = URL(string: audioURLString) else {
            throw CloudTTSError.invalidResponse("Missing output.audio.url")
        }

        // Download the WAV file from the returned URL
        let (audioData, audioResponse): (Data, URLResponse)
        do {
            var downloadRequest = URLRequest(url: audioURL)
            downloadRequest.timeoutInterval = 60
            (audioData, audioResponse) = try await URLSession.shared.data(for: downloadRequest)
        } catch {
            throw CloudTTSError.networkError("Audio download failed: \(error.localizedDescription)")
        }

        if let httpAudioResponse = audioResponse as? HTTPURLResponse,
           httpAudioResponse.statusCode != 200 {
            throw CloudTTSError.requestFailed(
                statusCode: httpAudioResponse.statusCode,
                message: "Audio download returned \(httpAudioResponse.statusCode)"
            )
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
