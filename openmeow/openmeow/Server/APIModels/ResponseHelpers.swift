import Foundation
import Hummingbird
import NIOFoundationCompat

nonisolated extension Response {
    static func json(_ value: some Encodable, status: HTTPResponse.Status = .ok) throws -> Response {
        let data = try JSONEncoder().encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    static func error(_ error: ErrorResponse, status: HTTPResponse.Status) -> Response {
        // Safe fallback: if encoding fails, return plain text
        guard let data = try? JSONEncoder().encode(error) else {
            return Response(
                status: status,
                headers: [.contentType: "text/plain"],
                body: .init(byteBuffer: .init(string: error.error.message))
            )
        }
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }
}
