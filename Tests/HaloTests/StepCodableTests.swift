import Testing
import Yams
@testable import Halo

/// The `Step` enum hand-rolls Codable so `config.yaml` can use compact, readable
/// forms — including a bare function name (`- clean`) and a qualified map
/// (`- translate: { lang: French }`). These verify the authoring shapes decode and
/// every case round-trips through YAML (the real serializer).
@Suite struct StepCodableTests {
    private func decodeSteps(_ yaml: String) throws -> [Step] {
        try YAMLDecoder().decode([Step].self, from: yaml)
    }
    private func roundTrip(_ steps: [Step]) throws -> [Step] {
        try YAMLDecoder().decode([Step].self, from: YAMLEncoder().encode(steps))
    }

    @Test func basicStepShapesDecode() throws {
        let yaml = """
        - key: cmd+s
        - text: hello
        - paste: 0
        - pause: 200
        - do: send
        - bash: echo hi
          inject: true
          as: greeting
        """
        let steps = try decodeSteps(yaml)
        #expect(steps[0] == .key(code: 1, modifiers: .command))
        #expect(steps[1] == .text("hello"))
        #expect(steps[2] == .paste(recent: 0))
        #expect(steps[3] == .pause(milliseconds: 200))
        #expect(steps[4] == .verb(.send))
        #expect(steps[5] == .bash(command: "echo hi", inject: true, name: "greeting"))
    }

    @Test func bareFunctionNameDecodesAsCallAndInject() throws {
        let steps = try decodeSteps("- clean\n")
        #expect(steps == [.function(name: "clean", vars: [:], provider: nil, inject: true, outputName: nil)])
    }

    @Test func qualifiedFunctionMapDecodes() throws {
        let yaml = """
        - translate:
            lang: French
          inject: false
          provider: openai
          as: out
        """
        let steps = try decodeSteps(yaml)
        #expect(steps == [.function(name: "translate", vars: ["lang": "French"],
                                    provider: "openai", inject: false, outputName: "out")])
    }

    @Test func everyStepCaseRoundTrips() throws {
        let steps: [Step] = [
            .key(code: 1, modifiers: [.command, .shift]),
            .text("literal text"),
            .paste(recent: 2),
            .pause(milliseconds: 50),
            .verb(.cancel),
            .bash(command: "ls -la", inject: false, name: nil),
            .function(name: "clean", vars: [:], provider: nil, inject: true, outputName: nil),
            .function(name: "translate", vars: ["lang": "German"], provider: "local", inject: false, outputName: "x"),
        ]
        #expect(try roundTrip(steps) == steps)
    }

    @Test func bareFunctionSerializesAsScalarNotMapping() throws {
        let steps: [Step] = [.function(name: "ask", vars: [:], provider: nil, inject: true, outputName: nil)]
        let yaml = try YAMLEncoder().encode(steps)
        #expect(yaml.contains("- ask"))                 // a scalar list item
        #expect(try roundTrip(steps) == steps)
    }

    @Test func emptyMappingStepIsRejected() {
        #expect(throws: (any Error).self) {
            _ = try YAMLDecoder().decode([Step].self, from: "- {}\n")
        }
    }
}
