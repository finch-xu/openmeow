import Foundation
import Hummingbird
import NIOFoundationCompat
import NIOCore

nonisolated enum ASRRoute {
    static func register(on router: Router<some RequestContext>, providerRouter: ProviderRouter) {
        router.post("v1/audio/transcriptions") { request, context in
            let cors = { (r: Response) in HTTPServer.withCORS(r, for: request) }
            if let authError = HTTPServer.checkAuth(request) { return cors(authError) }
            let contentType = request.headers[.contentType] ?? ""
            let mimeType = contentType.components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard mimeType == "multipart/form-data" else {
                return cors(Response.error(.invalidRequest("Content-Type must be multipart/form-data"), status: .badRequest))
            }

            let bodyData = try await request.body.collect(upTo: 50 * 1024 * 1024)

            guard let boundary = extractBoundary(from: contentType) else {
                return cors(Response.error(.invalidRequest("Missing multipart boundary"), status: .badRequest))
            }

            let parts = parseMultipart(data: Data(buffer: bodyData), boundary: boundary)

            guard let filePart = parts.first(where: { $0.name == "file" }) else {
                return cors(Response.error(.invalidRequest("Missing required field: file"), status: .badRequest))
            }

            let model = parts.first(where: { $0.name == "model" })?.stringValue
            let language = parts.first(where: { $0.name == "language" })?.stringValue
            let responseFormat = parts.first(where: { $0.name == "response_format" })?.stringValue ?? "json"

            guard let resolved = await providerRouter.resolveASR(model: model) else {
                if let model, !model.isEmpty {
                    return cors(Response.error(.modelNotFound(model), status: .notFound))
                }
                return cors(Response.error(.invalidRequest("No ASR model loaded"), status: .notFound))
            }

            do {
                let pcm = try AudioDecoder.decode(filePart.data, filenameHint: filePart.filename, contentTypeHint: filePart.contentType)
                let samples16k = AudioResampler.resample(pcm.samples, from: pcm.sampleRate, to: 16000)

                let result = try await resolved.provider.transcribe(
                    audio: samples16k, sampleRate: 16000, language: language, model: resolved.resolvedModel
                )

                let responseData = try formatASRResponse(result, format: responseFormat)
                let ct: String = responseFormat == "text" ? "text/plain" : "application/json"

                return cors(Response(
                    status: .ok,
                    headers: [.contentType: ct],
                    body: .init(byteBuffer: .init(data: responseData))
                ))
            } catch {
                return cors(Response.error(.invalidRequest("Transcription failed: \(error)"), status: .internalServerError))
            }
        }
    }

    // MARK: - Multipart Parsing

    private struct MultipartPart {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
        var stringValue: String? {
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func extractBoundary(from contentType: String) -> String? {
        for part in contentType.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("boundary=") {
                var boundary = String(trimmed.dropFirst("boundary=".count))
                if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                    boundary = String(boundary.dropFirst().dropLast())
                }
                return boundary
            }
        }
        return nil
    }

    private static func parseMultipart(data: Data, boundary: String) -> [MultipartPart] {
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let doubleCrlf = "\r\n\r\n".data(using: .utf8)!

        var parts: [MultipartPart] = []
        var searchRange = data.startIndex..<data.endIndex

        while let boundaryRange = data.range(of: boundaryData, in: searchRange) {
            let afterBoundary = boundaryRange.upperBound
            guard afterBoundary < data.endIndex else { break }
            if data[afterBoundary...].starts(with: "--".data(using: .utf8)!) { break }

            let headerStart = data.index(afterBoundary, offsetBy: 2, limitedBy: data.endIndex) ?? afterBoundary
            let remaining = headerStart..<data.endIndex
            guard let separatorRange = data.range(of: doubleCrlf, in: remaining) else { break }

            let headerData = data[headerStart..<separatorRange.lowerBound]
            let bodyStart = separatorRange.upperBound

            let bodySearchRange = bodyStart..<data.endIndex
            let bodyEnd: Data.Index
            if let nextBoundary = data.range(of: boundaryData, in: bodySearchRange) {
                bodyEnd = data.index(nextBoundary.lowerBound, offsetBy: -2, limitedBy: bodyStart) ?? nextBoundary.lowerBound
            } else {
                bodyEnd = data.endIndex
            }

            let bodyData = data[bodyStart..<bodyEnd]
            let headers = String(data: headerData, encoding: .utf8) ?? ""

            var name = ""
            var filename: String?
            var partContentType: String?

            for line in headers.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix("content-disposition:") {
                    if let n = extractHeaderParam(line, param: "name") { name = n }
                    filename = extractHeaderParam(line, param: "filename")
                } else if line.lowercased().hasPrefix("content-type:") {
                    partContentType = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                }
            }

            parts.append(MultipartPart(name: name, filename: filename, contentType: partContentType, data: Data(bodyData)))
            searchRange = (bodyEnd < data.endIndex ? bodyEnd : data.endIndex)..<data.endIndex
        }
        return parts
    }

    private static func extractHeaderParam(_ header: String, param: String) -> String? {
        let pattern = "\(param)=\""
        guard let range = header.range(of: pattern) else { return nil }
        let after = header[range.upperBound...]
        guard let endQuote = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<endQuote])
    }

    // MARK: - Response Formatting

    private static func formatASRResponse(_ result: ASRResult, format: String) throws -> Data {
        switch format {
        case "text": return result.text.data(using: .utf8)!
        default: return try JSONEncoder().encode(["text": result.text])
        }
    }
}
