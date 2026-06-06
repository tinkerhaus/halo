import Testing
import Yams
@testable import Halo

@Suite struct HaloConfigTests {
    private func decode(_ yaml: String) throws -> HaloConfig {
        try YAMLDecoder().decode(HaloConfig.self, from: yaml)
    }

    // MARK: lenient decoding

    @Test func minimalConfigDecodesWithDefaults() throws {
        let cfg = try decode("summonButton: 4\n")
        #expect(cfg.summonButton == 4)
        #expect(cfg.llm == nil)
        #expect(cfg.functions == nil)
        #expect(cfg.context == nil)
    }

    @Test func legacyFallbackKeyIsReadAsDefault() throws {
        // `fallback` is the deprecated alias for `default`; old configs must still load.
        let yaml = """
        summonButton: 4
        fallback:
          radius: 123
          arc: { spanDegrees: 270, centerDegrees: -90 }
          spokes: []
        """
        #expect(try decode(yaml).defaultHalo.radius == 123)
    }

    @Test func llmFunctionsAndContextRoundTrip() throws {
        let cfg = HaloConfig(
            summonButton: 4, sounds: true, voice: VoiceConfig(),
            llm: LLMConfig(providers: ["local": LLMProvider(baseURL: "http://localhost:11434/v1", model: "gemma")],
                           defaultProvider: "local"),
            functions: ["clean": Function(prompt: "Clean up the dictation.")],
            context: ContextConfig(lines: 12),
            defaultHalo: Halo(), profiles: [])
        let back = try decode(YAMLEncoder().encode(cfg))
        #expect(back.llm == cfg.llm)
        #expect(back.functions == cfg.functions)
        #expect(back.context == cfg.context)
    }

    // MARK: profile resolution

    @Test func activeProfilePrefersMatchingWhenOverPlain() {
        let plain = Profile(name: "Terminal", appBundleIDs: ["com.apple.Terminal"], halo: Halo())
        let dynamic = Profile(name: "Claude", appBundleIDs: ["com.apple.Terminal"], halo: Halo(),
                              when: WhenMatch(process: "claude"))
        let cfg = HaloConfig(defaultHalo: Halo(), profiles: [plain, dynamic])
        #expect(cfg.activeProfile(forApp: "com.apple.Terminal") { _ in true }?.name == "Claude")
        #expect(cfg.activeProfile(forApp: "com.apple.Terminal") { _ in false }?.name == "Terminal")
    }

    @Test func activeProfilePrefersMostSpecific() {
        let group = Profile(name: "Browsers", appBundleIDs: ["com.apple.Safari", "com.google.Chrome"], halo: Halo())
        let specific = Profile(name: "Safari", appBundleIDs: ["com.apple.Safari"], halo: Halo())
        let cfg = HaloConfig(defaultHalo: Halo(), profiles: [group, specific])
        #expect(cfg.activeProfile(forApp: "com.apple.Safari") { _ in false }?.name == "Safari")
    }

    @Test func activeProfileNilWhenNoAppMatches() {
        let cfg = HaloConfig(defaultHalo: Halo(),
                             profiles: [Profile(name: "X", appBundleIDs: ["a"], halo: Halo())])
        #expect(cfg.activeProfile(forApp: "other") { _ in true } == nil)
        #expect(cfg.activeProfile(forApp: nil) { _ in true } == nil)
    }

    // MARK: context resolution order

    @Test func contextConfigResolutionOrder() {
        let profileCtx = Profile(name: "Term", appBundleIDs: ["x"], halo: Halo(), context: ContextConfig(bash: "cmd"))
        let cfg = HaloConfig(summonButton: 4, sounds: true, voice: VoiceConfig(),
                             context: ContextConfig(lines: 5), defaultHalo: Halo(), profiles: [profileCtx])
        #expect(cfg.contextConfig(forApp: "x").bash == "cmd")     // profile override wins
        #expect(cfg.contextConfig(forApp: "other").lines == 5)    // else the global default
        #expect(HaloConfig(defaultHalo: Halo(), profiles: []).contextConfig(forApp: "y").lines == 12)  // else built-in AX
    }

    @Test func profileWithWhenAndContextRoundTrips() throws {
        let p = Profile(name: "Claude", appBundleIDs: ["com.apple.Terminal"], halo: Halo(),
                        context: ContextConfig(bash: "tmux capture-pane -p"),
                        when: WhenMatch(process: "claude", titleMatches: "task"))
        let back = try decode(YAMLEncoder().encode(HaloConfig(defaultHalo: Halo(), profiles: [p])))
        #expect(back.profiles.first == p)
    }
}
