import Foundation
import Hummingbird

nonisolated enum VoicesRoute {
    static func register(on router: Router<some RequestContext>, providerRouter: ProviderRouter) {
        router.get("v1/voices") { request, _ in
            let cors = { (r: Response) in HTTPServer.withCORS(r, for: request) }
            if let authError = HTTPServer.checkAuth(request) { return cors(authError) }
            let model = request.uri.queryParameters.get("model") ?? ""
            let voices: [VoiceInfo]
            if model.isEmpty {
                voices = await providerRouter.allVoices()
            } else {
                voices = await providerRouter.voices(for: model)
            }
            return cors(try Response.json(VoicesListResponse(voices: voices)))
        }
    }
}

nonisolated struct VoicesListResponse: Codable, Sendable {
    let voices: [VoiceInfo]
}
