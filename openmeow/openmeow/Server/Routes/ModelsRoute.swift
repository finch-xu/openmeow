import Foundation
import Hummingbird

nonisolated enum ModelsRoute {
    static func register(on router: Router<some RequestContext>, providerRouter: ProviderRouter) {
        router.get("v1/models") { request, _ in
            let cors = { (r: Response) in HTTPServer.withCORS(r, for: request) }
            if let authError = HTTPServer.checkAuth(request) { return cors(authError) }
            let models = await providerRouter.allModels()
            return cors(try Response.json(ModelsListResponse(
                object: "list",
                data: models.map { m in
                    ModelObject(
                        id: m.apiId ?? m.id, object: "model", created: 0,
                        owned_by: m.provider, type: m.type, ready: m.ready
                    )
                }
            )))
        }
    }
}

nonisolated struct ModelsListResponse: Codable, Sendable {
    let object: String
    let data: [ModelObject]
}

nonisolated struct ModelObject: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let owned_by: String
    let type: String
    let ready: Bool
}
