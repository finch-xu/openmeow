import Hummingbird

nonisolated enum HealthRoute {
    static func register(on router: Router<some RequestContext>) {
        router.get("health") { request, _ in
            HTTPServer.withCORS(
                try Response.json(HealthResponse(status: "ok", version: AppConstants.version)),
                for: request
            )
        }
    }
}
