import Testing
@testable import Halo

@Suite struct FunctionInterpolationTests {
    @Test func substitutesKnownVariables() {
        #expect(Function.interpolate("Translate to {lang}.", ["lang": "French"]) == "Translate to French.")
    }

    @Test func missingVariableBecomesEmpty() {
        #expect(Function.interpolate("Hi {name}!", [:]) == "Hi !")
    }

    @Test func multipleAndRepeatedVariables() {
        #expect(Function.interpolate("{a}-{b}-{a}", ["a": "1", "b": "2"]) == "1-2-1")
    }

    @Test func underscoreAndDigitIdentifiersAreValid() {
        #expect(Function.interpolate("{my_var1}", ["my_var1": "ok"]) == "ok")
    }

    @Test func nonIdentifierBracesPassThroughUntouched() {
        // JSON-ish content / spaces aren't `{identifier}` spans
        #expect(Function.interpolate("{ \"a\": 1 }", ["a": "X"]) == "{ \"a\": 1 }")
        #expect(Function.interpolate("a {b c} d", ["b": "X"]) == "a {b c} d")
    }

    @Test func unterminatedBracePassesThrough() {
        #expect(Function.interpolate("open { brace", ["brace": "X"]) == "open { brace")
    }

    @Test func templateWithoutBracesIsIdentity() {
        #expect(Function.interpolate("plain text", ["a": "X"]) == "plain text")
    }
}
