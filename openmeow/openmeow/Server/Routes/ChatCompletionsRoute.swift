import Foundation
import Hummingbird
import NIOFoundationCompat
import HTTPTypes

nonisolated enum ChatCompletionsRoute {
    static func register(on router: Router<some RequestContext>, providerRouter: ProviderRouter) {
        router.post("v1/chat/completions") { request, context in
            let cors = { (r: Response) in HTTPServer.withCORS(r, for: request) }
            if let authError = HTTPServer.checkAuth(request) { return cors(authError) }

            let body: ChatCompletionsRequest
            do {
                body = try await request.decode(as: ChatCompletionsRequest.self, context: context)
            } catch {
                return cors(Response.error(.invalidRequest("Invalid request body"), status: .badRequest))
            }

            // Extract text from the last assistant message
            guard let assistantMessage = body.messages.last(where: { $0.role == "assistant" }) else {
                return cors(Response.error(.invalidRequest("No assistant message found in messages"), status: .badRequest))
            }

            let text = assistantMessage.content
            guard !text.isEmpty else {
                return cors(Response.error(.invalidRequest("Assistant message content is empty"), status: .badRequest))
            }
            guard text.count <= 10_000 else {
                return cors(Response.error(.invalidRequest("Input text exceeds 10,000 character limit"), status: .badRequest))
            }

            guard let resolved = await providerRouter.resolveTTS(model: body.model) else {
                return cors(Response.error(.modelNotFound(body.model), status: .notFound))
            }

            let voice = body.audio?.voice ?? "af_heart"
            let format = resolveFormat(body.audio?.format)
            guard let responseFormat = format else {
                return cors(Response.error(.invalidRequest("Unsupported audio format: \(body.audio?.format ?? "nil")"), status: .badRequest))
            }

            do {
                let audioBuffer = try await resolved.provider.generate(
                    text: text, voice: voice, speed: 1.0, model: resolved.resolvedModel
                )
                let data = try AudioEncoder.encode(audioBuffer, format: responseFormat)
                let base64Audio = data.base64EncodedString()

                let response = ChatCompletionsResponse(
                    id: "chatcmpl-\(UUID().uuidString)",
                    object: "chat.completion",
                    created: Int(Date().timeIntervalSince1970),
                    model: body.model,
                    choices: [
                        ChatChoice(
                            index: 0,
                            message: ChatResponseMessage(
                                role: "assistant",
                                content: text,
                                audio: ChatAudioData(data: base64Audio)
                            ),
                            finish_reason: "stop"
                        )
                    ],
                    usage: ChatUsage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
                )

                return cors(try Response.json(response))
            } catch {
                return cors(Response.error(.invalidRequest("Generation failed: \(error)"), status: .internalServerError))
            }
        }
    }

    /// Map chat-style format strings to ResponseFormat, handling aliases like "pcm16".
    private static func resolveFormat(_ format: String?) -> ResponseFormat? {
        guard let format else { return .wav }
        switch format {
        case "pcm16": return .pcm
        default: return ResponseFormat(rawValue: format)
        }
    }
}
