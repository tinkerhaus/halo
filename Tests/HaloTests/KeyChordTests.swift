import Testing
@testable import Halo

@Suite struct KeyChordTests {
    @Test func parsesModifierAliases() {
        #expect(KeyChord.parse("command+s")?.modifiers == .command)
        #expect(KeyChord.parse("cmd+s")?.modifiers == .command)
        #expect(KeyChord.parse("option+a")?.modifiers == .option)
        #expect(KeyChord.parse("alt+a")?.modifiers == .option)
        #expect(KeyChord.parse("control+c")?.modifiers == .control)
        #expect(KeyChord.parse("ctrl+c")?.modifiers == .control)
    }

    @Test func isCaseInsensitiveAndTrimsSpaces() {
        #expect(KeyChord.parse("CMD + Shift + Z")?.code == KeyChord.parse("cmd+shift+z")?.code)
        #expect(KeyChord.parse("CMD + Shift + Z")?.modifiers == [.command, .shift])
    }

    @Test func formatsInCanonicalOrderRegardlessOfInput() {
        // canonical order is ctrl, opt, shift, cmd
        let p = KeyChord.parse("cmd+ctrl+shift+opt+a")!
        #expect(KeyChord.format(code: p.code, modifiers: p.modifiers) == "ctrl+opt+shift+cmd+a")
    }

    @Test func namedAndPunctuationKeysRoundTrip() {
        for chord in ["return", "esc", "up", "down", "cmd+[", "shift+tab", "ctrl+`", "cmd+/", "opt+="] {
            let p = KeyChord.parse(chord)
            #expect(p != nil, "parse failed for \(chord)")
            if let p {
                let reparsed = KeyChord.parse(KeyChord.format(code: p.code, modifiers: p.modifiers))
                #expect(reparsed?.code == p.code && reparsed?.modifiers == p.modifiers)
            }
        }
    }

    @Test func canonicalNameUsedWhenFormatting() {
        // "enter" is an alias of the canonical "return" (both code 36)
        let p = KeyChord.parse("enter")!
        #expect(KeyChord.format(code: p.code, modifiers: []) == "return")
        #expect(KeyChord.parse("backspace")?.code == KeyChord.parse("delete")?.code)
    }

    @Test func rejectsUnknownTokens() {
        #expect(KeyChord.parse("cmd+notakey") == nil)   // unknown key
        #expect(KeyChord.parse("hyper+a") == nil)        // unknown modifier
        #expect(KeyChord.parse("") == nil)               // empty
    }

    @Test func rawKeyCodeFallbackRoundTrips() {
        // format emits key<code> for unmapped codes; parse reads it back
        let s = KeyChord.format(code: 200, modifiers: [.command])
        #expect(s == "cmd+key200")
        #expect(KeyChord.parse(s)?.code == 200)
    }
}
