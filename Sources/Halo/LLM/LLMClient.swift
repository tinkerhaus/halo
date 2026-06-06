import Foundation

/// A minimal OpenAI-compatible Chat Completions client. Talks to any endpoint
/// that speaks `POST /v1/chat/completions` — a local vLLM / Ollama / LM Studio
/// server, or a cloud provider with a key. Non-streaming for now: one request,
/// one string back.
///
/// Stateless and dependency-free (`URLSession` + `Codable`). The caller resolves
/// the API key (from the Keychain) and hands it in; we just attach the header.
enum LLMClient {
    /// A resolved endpoint: the key is already looked up (nil = no auth header).
    struct Provider {
        var baseURL: String        // up to and including `/v1`
        var model: String
        var apiKey: String?
        var thinking: Bool = true  // false ⇒ ask the server to disable the model's thinking
    }

    enum LLMError: LocalizedError {
        case badURL(String)
        case http(Int, String)     // status + (truncated) body
        case empty                 // no choices / empty content

        var errorDescription: String? {
            switch self {
            case .badURL(let u): return "Bad LLM base URL: \(u)"
            case .http(let code, let body): return "LLM HTTP \(code): \(body)"
            case .empty: return "LLM returned no text"
            }
        }
    }

    // MARK: - Wire types

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let stream = false
        let temperature: Double
        var chatTemplateKwargs: [String: Bool]? = nil   // e.g. {enable_thinking: false} (llama.cpp/vLLM)

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature, chatTemplateKwargs = "chat_template_kwargs"
        }
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    /// Run a single-turn completion: `system` instruction + `user` content.
    /// Calls back (on a `URLSession` background queue) with the assistant text or
    /// an error. Times out at 30s.
    static func complete(provider: Provider, system: String, user: String, temperature: Double = 0.2,
                         completion: @escaping (Result<String, Error>) -> Void) {
        let base = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
        guard let url = URL(string: base + "/chat/completions") else {
            return completion(.failure(LLMError.badURL(provider.baseURL)))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = provider.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var messages = [Request.Message]()
        if !system.isEmpty { messages.append(.init(role: "system", content: system)) }
        messages.append(.init(role: "user", content: user))
        var body = Request(model: provider.model, messages: messages, temperature: temperature)
        if !provider.thinking { body.chatTemplateKwargs = ["enable_thinking": false] }   // reasoning off
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return completion(.failure(error))
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }
            let data = data ?? Data()
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return completion(.failure(LLMError.http(http.statusCode, body)))
            }
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
                  let text = decoded.choices.first?.message.content?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return completion(.failure(LLMError.empty))
            }
            completion(.success(text))
        }.resume()
    }
}
