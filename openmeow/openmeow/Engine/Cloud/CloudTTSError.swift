import Foundation

nonisolated enum CloudTTSError: Error, LocalizedError {
    case apiKeyNotConfigured
    case invalidEndpoint(String)
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse(String)
    case audioDecodingFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            "API key not configured"
        case .invalidEndpoint(let url):
            "Invalid endpoint URL: \(url)"
        case .requestFailed(let code, let msg):
            "Request failed (\(code)): \(msg)"
        case .invalidResponse(let detail):
            "Invalid response: \(detail)"
        case .audioDecodingFailed(let detail):
            "Audio decoding failed: \(detail)"
        case .networkError(let detail):
            "Network error: \(detail)"
        }
    }
}
