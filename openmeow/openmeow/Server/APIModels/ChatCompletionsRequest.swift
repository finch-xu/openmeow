import Foundation

// MARK: - Request

nonisolated struct ChatCompletionsRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let audio: ChatAudioOptions?
}

nonisolated struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

nonisolated struct ChatAudioOptions: Codable, Sendable {
    let format: String?
    let voice: String?
}

// MARK: - Response

nonisolated struct ChatCompletionsResponse: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: ChatUsage
}

nonisolated struct ChatChoice: Codable, Sendable {
    let index: Int
    let message: ChatResponseMessage
    let finish_reason: String
}

nonisolated struct ChatResponseMessage: Codable, Sendable {
    let role: String
    let content: String
    let audio: ChatAudioData?
}

nonisolated struct ChatAudioData: Codable, Sendable {
    let data: String
}

nonisolated struct ChatUsage: Codable, Sendable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}
