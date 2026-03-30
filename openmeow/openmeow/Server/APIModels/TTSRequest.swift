import Foundation

nonisolated struct TTSRequest: Codable, Sendable {
    let model: String
    let input: String
    let voice: String?
    let speed: Double?
    let response_format: String?
}
