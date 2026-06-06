import Testing
import Yams
@testable import Halo

@Suite struct LLMConfigCodableTests {

    // MARK: provider(named:) resolution

    @Test func resolvesNamedThenDefault() {
        let cfg = LLMConfig(providers: [
            "local": LLMProvider(baseURL: "http://localhost:11434/v1", model: "gemma"),
            "openai": LLMProvider(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", keyRef: "openai"),
        ], defaultProvider: "local")
        #expect(cfg.provider(named: "openai")?.model == "gpt-4o-mini")   // explicit name
        #expect(cfg.provider(named: nil)?.model == "gemma")              // → configured default
        #expect(cfg.provider(named: "missing")?.model == "gemma")        // unknown name → default
    }

    @Test func resolvesSoleProviderWhenNoDefault() {
        let cfg = LLMConfig(providers: ["only": LLMProvider(baseURL: "u", model: "m")])
        #expect(cfg.provider(named: nil)?.model == "m")
    }

    @Test func returnsNilWhenAmbiguous() {
        let cfg = LLMConfig(providers: [
            "a": LLMProvider(baseURL: "x", model: "1"),
            "b": LLMProvider(baseURL: "y", model: "2"),
        ])
        #expect(cfg.provider(named: nil) == nil)   // two providers, no default
    }

    // MARK: compact serialization (`base` key, omit empties)

    @Test func providerOmitsEmptyKeyRefAndThinking() throws {
        let yaml = try YAMLEncoder().encode(LLMProvider(baseURL: "u", model: "m"))
        #expect(yaml.contains("base:"))            // baseURL serializes as `base`
        #expect(!yaml.contains("keyRef"))
        #expect(!yaml.contains("thinking"))
    }

    @Test func providerRoundTrips() throws {
        let p = LLMProvider(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", keyRef: "openai", thinking: false)
        #expect(try YAMLDecoder().decode(LLMProvider.self, from: YAMLEncoder().encode(p)) == p)
    }

    @Test func functionOmitsEmptyOptionalFields() throws {
        let yaml = try YAMLEncoder().encode(Function(prompt: "Clean it."))
        #expect(yaml.contains("prompt:"))
        #expect(!yaml.contains("variables"))
        #expect(!yaml.contains("temperature"))
    }

    @Test func functionRoundTrips() throws {
        let f = Function(prompt: "Translate to {lang}.", variables: ["lang": "English"], provider: "openai", temperature: 0.5)
        #expect(try YAMLDecoder().decode(Function.self, from: YAMLEncoder().encode(f)) == f)
    }

    @Test func contextConfigRoundTrips() throws {
        let lines = ContextConfig(lines: 20)
        #expect(try YAMLDecoder().decode(ContextConfig.self, from: YAMLEncoder().encode(lines)) == lines)
        let bash = ContextConfig(bash: "tmux capture-pane -p")
        #expect(try YAMLDecoder().decode(ContextConfig.self, from: YAMLEncoder().encode(bash)) == bash)
    }

    @Test func whenMatchEmptinessAndRoundTrip() throws {
        #expect(WhenMatch().isEmpty)
        #expect(!WhenMatch(process: "claude").isEmpty)
        let w = WhenMatch(process: "claude", titleMatches: "building")
        #expect(try YAMLDecoder().decode(WhenMatch.self, from: YAMLEncoder().encode(w)) == w)
    }

    @Test func llmConfigOmitsEmptyDefault() throws {
        let yaml = try YAMLEncoder().encode(LLMConfig(providers: ["a": LLMProvider(baseURL: "u", model: "m")]))
        #expect(!yaml.contains("default:"))
    }
}
