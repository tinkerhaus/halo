import Foundation

/// One OpenAI-compatible chat endpoint Halo can call — a local server
/// (vLLM / Ollama / LM Studio) or a cloud provider. The API key, when one is
/// needed, is **not** stored here: `keyRef` names a Keychain item (service
/// "Halo") that holds the secret, so `config.yaml` stays free of credentials.
/// Local servers usually need no auth — omit `keyRef`.
///
/// Serializes compactly: `{ base, model, keyRef? }`.
struct LLMProvider: Codable, Equatable {
    var baseURL: String        // e.g. "http://localhost:11434/v1" or "https://api.openai.com/v1"
    var model: String          // e.g. "gemma-4-e4b", "gpt-4o-mini"
    var keyRef: String?        // Keychain item name (NOT the key itself); nil = no Authorization header
    var thinking: Bool?        // set false to disable a reasoning model's thinking (faster); nil = leave default

    init(baseURL: String, model: String, keyRef: String? = nil, thinking: Bool? = nil) {
        self.baseURL = baseURL; self.model = model; self.keyRef = keyRef; self.thinking = thinking
    }

    private enum K: String, CodingKey { case baseURL = "base", model, keyRef, thinking }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        if let keyRef, !keyRef.isEmpty { try c.encode(keyRef, forKey: .keyRef) }   // omit when no auth
        if let thinking { try c.encode(thinking, forKey: .thinking) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? ""
        keyRef = (try? c.decode(String.self, forKey: .keyRef)).flatMap { $0.isEmpty ? nil : $0 }
        thinking = try? c.decode(Bool.self, forKey: .thinking)
    }
}

/// The providers Halo knows about, plus which to use when an `llm` step doesn't
/// name one. The whole block is optional in `config.yaml`; omit it and any `llm`
/// step degrades gracefully — it passes its input through untouched (see
/// `AppController.runLLM`), so words are never lost when nothing is configured.
struct LLMConfig: Codable, Equatable {
    var providers: [String: LLMProvider]
    var defaultProvider: String?

    init(providers: [String: LLMProvider] = [:], defaultProvider: String? = nil) {
        self.providers = providers; self.defaultProvider = defaultProvider
    }

    private enum K: String, CodingKey { case providers, defaultProvider = "default" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(providers, forKey: .providers)
        if let defaultProvider, !defaultProvider.isEmpty { try c.encode(defaultProvider, forKey: .defaultProvider) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        providers = (try? c.decodeIfPresent([String: LLMProvider].self, forKey: .providers)) ?? [:]
        defaultProvider = (try? c.decode(String.self, forKey: .defaultProvider)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Resolve the provider for a step: the named one, else the configured
    /// `default`, else the sole provider when there's exactly one. nil if none fit.
    func provider(named name: String?) -> LLMProvider? {
        if let name, let p = providers[name] { return p }
        if let d = defaultProvider, let p = providers[d] { return p }
        if providers.count == 1 { return providers.values.first }
        return nil
    }
}

/// A named, reusable **function** — the thing a spoke calls (`clean`, `translate`, …).
/// Its definition holds a `prompt` (the instruction) and its `variables` (name →
/// default value). The `prompt` interpolates `{variables}` plus built-ins: the
/// dictation as `{transcript}`, any value passed at the call site, and earlier
/// `as:` outputs. The dictation is the function's input. `provider` (optional)
/// overrides the default engine for this function.
///
/// Serializes as `{ prompt, variables?, provider?, temperature? }`.
struct Function: Codable, Equatable {
    var prompt: String
    var variables: [String: String]?
    var provider: String?
    var temperature: Double?

    init(prompt: String, variables: [String: String]? = nil, provider: String? = nil, temperature: Double? = nil) {
        self.prompt = prompt; self.variables = variables; self.provider = provider; self.temperature = temperature
    }

    private enum K: String, CodingKey { case prompt, variables, provider, temperature }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(prompt, forKey: .prompt)
        if let variables, !variables.isEmpty { try c.encode(variables, forKey: .variables) }
        if let provider, !provider.isEmpty { try c.encode(provider, forKey: .provider) }
        if let temperature { try c.encode(temperature, forKey: .temperature) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        variables = (try? c.decode([String: String].self, forKey: .variables)).flatMap { $0.isEmpty ? nil : $0 }
        provider = (try? c.decode(String.self, forKey: .provider)).flatMap { $0.isEmpty ? nil : $0 }
        temperature = try? c.decode(Double.self, forKey: .temperature)
    }

    /// Substitute `{name}` placeholders with `vars[name]` (a missing var → empty).
    /// Only well-formed `{identifier}` spans are touched; other braces pass through.
    static func interpolate(_ template: String, _ vars: [String: String]) -> String {
        guard template.contains("{") else { return template }
        var result = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let close = template[i...].firstIndex(of: "}") {
                let key = String(template[template.index(after: i)..<close])
                if !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    result += vars[key] ?? ""
                    i = template.index(after: close)
                    continue
                }
            }
            result.append(template[i])
            i = template.index(after: i)
        }
        return result
    }
}

/// How an app supplies the `{context}` a function can interpolate. With `bash`, runs
/// a command and uses its stdout (e.g. `tmux capture-pane` for a terminal). Otherwise
/// reads up to `lines` lines of text *before the caret* via Accessibility (default 12).
/// Resolves to "" when the app exposes no text (terminals without the override, many
/// Electron apps) — the function then simply runs without context. Set per-profile, or
/// globally, under `context:`. Captured only when a function's prompt mentions `{context}`.
struct ContextConfig: Codable, Equatable {
    var lines: Int?
    var bash: String?

    init(lines: Int? = nil, bash: String? = nil) { self.lines = lines; self.bash = bash }

    /// The built-in default when nothing is configured: lines before the caret via AX.
    static let defaultAX = ContextConfig(lines: 12)

    private enum K: String, CodingKey { case lines, bash }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        if let lines { try c.encode(lines, forKey: .lines) }
        if let bash, !bash.isEmpty { try c.encode(bash, forKey: .bash) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        lines = try? c.decode(Int.self, forKey: .lines)
        bash = (try? c.decode(String.self, forKey: .bash)).flatMap { $0.isEmpty ? nil : $0 }
    }
}
