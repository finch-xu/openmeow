import Foundation
import Hummingbird
import NIOFoundationCompat
import HTTPTypes

nonisolated enum TTSRoute {
    static func register(on router: Router<some RequestContext>, providerRouter: ProviderRouter) {
        router.post("v1/audio/speech") { request, context in
            let cors = { (r: Response) in HTTPServer.withCORS(r, for: request) }
            if let authError = HTTPServer.checkAuth(request) { return cors(authError) }
            let body: TTSRequest
            do {
                body = try await request.decode(as: TTSRequest.self, context: context)
            } catch {
                return cors(Response.error(.invalidRequest("Invalid request body"), status: .badRequest))
            }

            guard !body.input.isEmpty else {
                return cors(Response.error(.invalidRequest("Input text is empty"), status: .badRequest))
            }
            guard body.input.count <= 10_000 else {
                return cors(Response.error(.invalidRequest("Input text exceeds 10,000 character limit"), status: .badRequest))
            }

            let speed = Float(body.speed ?? 1.0)
            guard speed >= 0.25 && speed <= 4.0 else {
                return cors(Response.error(.invalidRequest("Speed must be between 0.25 and 4.0"), status: .badRequest))
            }

            guard let resolved = await providerRouter.resolveTTS(model: body.model) else {
                return cors(Response.error(.modelNotFound(body.model), status: .notFound))
            }

            let voice = body.voice ?? "af_heart"
            let defaultFormat = UserDefaults.standard.string(forKey: AppConstants.defaultTTSFormatKey) ?? "opus"
            let formatStr = body.response_format ?? defaultFormat
            guard let format = ResponseFormat(rawValue: formatStr) else {
                return cors(Response.error(.invalidRequest("Unsupported response_format: \(formatStr)"), status: .badRequest))
            }

            do {
                let audioBuffer = try await resolved.provider.generate(
                    text: body.input, voice: voice, speed: speed, model: resolved.resolvedModel
                )
                let data = try AudioEncoder.encode(audioBuffer, format: format)

                let contentType: String = switch format {
                case .wav: "audio/wav"
                case .mp3: "audio/mpeg"
                case .pcm: "audio/pcm"
                case .opus: "audio/opus"
                case .flac: "audio/flac"
                case .aac: "audio/aac"
                }

                return cors(Response(
                    status: .ok,
                    headers: [.contentType: contentType],
                    body: .init(byteBuffer: .init(data: data))
                ))
            } catch {
                return cors(Response.error(.invalidRequest("Generation failed: \(error)"), status: .internalServerError))
            }
        }
    }
}
