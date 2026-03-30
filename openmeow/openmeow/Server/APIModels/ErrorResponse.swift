import Foundation

nonisolated struct ErrorResponse: Codable, Sendable {
    nonisolated struct ErrorDetail: Codable, Sendable {
        let message: String
        let type: String
        let param: String?
        let code: String?
    }

    let error: ErrorDetail

    static func modelNotFound(_ model: String) -> ErrorResponse {
        ErrorResponse(error: ErrorDetail(
            message: "Model '\(model)' not found",
            type: "invalid_request_error",
            param: "model",
            code: "model_not_found"
        ))
    }

    static func invalidRequest(_ message: String) -> ErrorResponse {
        ErrorResponse(error: ErrorDetail(
            message: message,
            type: "invalid_request_error",
            param: nil,
            code: nil
        ))
    }
}

nonisolated struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
}
