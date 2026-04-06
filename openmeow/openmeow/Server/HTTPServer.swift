import Foundation
import Hummingbird
import HTTPTypes
import Logging

nonisolated enum HTTPServer {

    static func run(port: Int, listenAddress: String = "127.0.0.1", providerRouter: ProviderRouter) async throws {
        let router = Router()

        // CORS preflight handlers for each API path
        router.on("health", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }
        router.on("v1/models", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }
        router.on("v1/voices", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }
        router.on("v1/audio/speech", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }
        router.on("v1/audio/transcriptions", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }
        router.on("v1/chat/completions", method: .options) { r, _ in corsResponse(for: r, status: .noContent) }

        // Register all routes
        HealthRoute.register(on: router)
        TTSRoute.register(on: router, providerRouter: providerRouter)
        ASRRoute.register(on: router, providerRouter: providerRouter)
        ModelsRoute.register(on: router, providerRouter: providerRouter)
        VoicesRoute.register(on: router, providerRouter: providerRouter)
        ChatCompletionsRoute.register(on: router, providerRouter: providerRouter)

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(listenAddress, port: port)
            ),
            logger: Logger(label: "dev.pidan.openmeow.server")
        )

        try await app.runService()
    }

    // MARK: - CORS

    /// Get stored allowed IP patterns, defaulting to local.
    private static func allowedIPs() -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: AppConstants.corsOriginsKey) {
            return saved
        }
        return AppConstants.corsLocalOrigins
    }

    /// Extract hostname from an Origin header value like "http://192.168.1.5:8080" → "192.168.1.5"
    private static func extractHost(from origin: String) -> String? {
        // Handle "null" origin (file:// pages)
        if origin == "null" { return nil }
        // Strip scheme: "http://host:port" → "host:port"
        guard let schemeEnd = origin.range(of: "://") else { return nil }
        let hostPort = String(origin[schemeEnd.upperBound...])
        // Strip port: "host:port" → "host"
        if let colonIdx = hostPort.lastIndex(of: ":") {
            return String(hostPort[..<colonIdx])
        }
        return hostPort
    }

    /// Parse an IPv4 dotted-quad string to UInt32 (big-endian).
    private static func parseIPv4(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var addr: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            addr = addr << 8 | UInt32(octet)
        }
        return addr
    }

    /// Check if an IPv4 address falls within a CIDR range (e.g. "192.168.0.0/16").
    private static func ipMatchesCIDR(_ ip: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let network = parseIPv4(String(parts[0])),
              let prefixLen = UInt8(parts[1]),
              prefixLen <= 32 else { return false }
        guard let addr = parseIPv4(ip) else { return false }
        guard prefixLen > 0 else { return true }
        let mask: UInt32 = ~(UInt32.max >> prefixLen)
        return (addr & mask) == (network & mask)
    }

    /// Check if a request Origin is allowed by the configured IP patterns.
    private static func matchOrigin(_ origin: String) -> String? {
        let patterns = allowedIPs()
        if patterns.contains("*") { return "*" }

        // file:// pages send "null" — only allow if "null" is explicitly in the allowed list
        if origin == "null" { return patterns.contains("null") ? "null" : nil }

        guard let host = extractHost(from: origin) else { return nil }

        for pattern in patterns {
            if host == pattern { return origin }
            if pattern.contains("/") && ipMatchesCIDR(host, cidr: pattern) { return origin }
        }
        return nil
    }

    /// Build a CORS preflight response.
    static func corsResponse(for request: Request, status: HTTPResponse.Status = .ok) -> Response {
        var headers = HTTPFields()
        guard UserDefaults.standard.bool(forKey: AppConstants.corsEnabledKey) else {
            return Response(status: status, headers: headers)
        }
        let origin = request.headers[.origin] ?? "null"
        if let allowed = matchOrigin(origin) {
            headers[.accessControlAllowOrigin] = allowed
            headers[.accessControlAllowMethods] = "GET, POST, OPTIONS"
            headers[.accessControlAllowHeaders] = "Content-Type, Authorization"
            headers[.accessControlMaxAge] = "86400"
            if allowed != "*" { headers[.vary] = "Origin" }
        }
        return Response(status: status, headers: headers)
    }

    /// Add CORS headers to an existing response if origin is allowed.
    static func withCORS(_ response: Response, for request: Request) -> Response {
        guard UserDefaults.standard.bool(forKey: AppConstants.corsEnabledKey) else { return response }
        let origin = request.headers[.origin] ?? "null"
        guard let allowed = matchOrigin(origin) else { return response }
        var response = response
        response.headers[.accessControlAllowOrigin] = allowed
        if allowed != "*" { response.headers[.vary] = "Origin" }
        return response
    }

    // MARK: - Auth

    /// Check bearer token auth. Returns an error Response if unauthorized, nil if OK.
    static func checkAuth(_ request: Request) -> Response? {
        guard UserDefaults.standard.bool(forKey: AppConstants.authEnabledKey) else { return nil }
        guard let savedToken = UserDefaults.standard.string(forKey: AppConstants.authTokenKey),
              !savedToken.isEmpty else { return nil }

        if let authHeader = request.headers[.authorization] {
            let expected = "Bearer \(savedToken)"
            // Constant-time comparison to prevent timing side-channel
            if constantTimeEqual(authHeader, expected) {
                return nil
            }
        }

        return Response(status: .unauthorized, headers: [.wwwAuthenticate: "Bearer realm=\"openmeow\""])
    }

    /// Constant-time string comparison to prevent timing attacks.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }
}
