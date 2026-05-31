import Foundation

/// macOS virtual key codes, named for readability where we use them.
enum Key {
    static let enter: UInt16 = 36, esc: UInt16 = 53, tab: UInt16 = 48, delete: UInt16 = 51
    static let up: UInt16 = 126, down: UInt16 = 125, left: UInt16 = 123, right: UInt16 = 124
    static let c: UInt16 = 8, d: UInt16 = 2, r: UInt16 = 15, u: UInt16 = 32, l: UInt16 = 37
    static let s: UInt16 = 1, z: UInt16 = 6, f: UInt16 = 3, t: UInt16 = 17, w: UInt16 = 13
    static let slash: UInt16 = 44, leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
}

/// A halo bound to a set of apps. The frontmost app picks the profile; if none
/// match, the `fallback` halo is used.
struct Profile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var appBundleIDs: [String]
    var halo: Halo
}

/// Halo's whole configuration: a fallback halo plus per-app profiles. This is
/// what persists to disk and what the editor edits.
struct Configuration: Codable, Equatable {
    var fallback: Halo
    var profiles: [Profile]

    /// The halo to summon for a given frontmost app.
    func halo(forApp bundleID: String?) -> Halo {
        if let bundleID, let match = profiles.first(where: { $0.appBundleIDs.contains(bundleID) }) {
            return match.halo
        }
        return fallback
    }

    // MARK: - Starter configuration

    static func starter() -> Configuration {
        Configuration(fallback: fallbackHalo(),
                      profiles: [terminalProfile(), browserProfile(), editorProfile()])
    }

    private static func arc(_ span: Double) -> Arc { Arc(spanDegrees: span, centerDegrees: -90) }

    private static func fallbackHalo() -> Halo {
        Halo(arc: arc(200), spokes: [
            .action("Enter", "return", .key(Key.enter)),
            .action("Up", "arrow.up", .key(Key.up)),
            .action("Down", "arrow.down", .key(Key.down)),
            .action("Esc", "escape", .key(Key.esc)),
            .action("Delete", "delete.left", .key(Key.delete)),
            .well("Nav", "arrow.up.and.down.and.arrow.left.and.right",
                  Halo(arc: arc(180), spokes: [
                    .action("Left", "arrow.left", .key(Key.left)),
                    .action("Right", "arrow.right", .key(Key.right)),
                  ])),
        ])
    }

    private static func terminalProfile() -> Profile {
        Profile(name: "Terminal / Agent",
                appBundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                               "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty",
                               "com.github.wez.wezterm"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Enter", "return", .key(Key.enter)),
                    .action("Up", "arrow.up", .key(Key.up)),
                    .action("Down", "arrow.down", .key(Key.down)),
                    .action("Tab", "arrow.right.to.line", .key(Key.tab)),
                    .action("Esc", "escape", .key(Key.esc)),
                    .action("Stop", "stop.circle", .key(Key.c, .control)),
                    .well("More", "ellipsis.circle", Halo(arc: arc(180), spokes: [
                        .action("⇧Tab", "arrow.left.to.line", .key(Key.tab, .shift)),
                        .action("Search", "magnifyingglass", .key(Key.r, .control)),
                        .action("Clear", "delete.left", .key(Key.u, .control)),
                        .action("EOF", "eject", .key(Key.d, .control)),
                        .action("Cls", "rectangle.dashed", .key(Key.l, .control)),
                    ])),
                ]))
    }

    private static func browserProfile() -> Profile {
        Profile(name: "Browser",
                appBundleIDs: ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                               "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Back", "chevron.left", .key(Key.leftBracket, .command)),
                    .action("Forward", "chevron.right", .key(Key.rightBracket, .command)),
                    .action("Reload", "arrow.clockwise", .key(Key.r, .command)),
                    .action("New Tab", "plus.square", .key(Key.t, .command)),
                    .action("Close", "xmark.square", .key(Key.w, .command)),
                    .action("Find", "magnifyingglass", .key(Key.f, .command)),
                    .well("Tabs", "ellipsis.circle", Halo(arc: arc(160), spokes: [
                        .action("Address", "link", .key(Key.l, .command)),
                        .action("Next Tab", "chevron.right.2", .key(Key.tab, .control)),
                        .action("Prev Tab", "chevron.left.2", .key(Key.tab, [.control, .shift])),
                    ])),
                ]))
    }

    private static func editorProfile() -> Profile {
        Profile(name: "Editor / IDE",
                appBundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                               "com.apple.dt.Xcode", "dev.zed.Zed"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Save", "square.and.arrow.down", .key(Key.s, .command)),
                    .action("Undo", "arrow.uturn.backward", .key(Key.z, .command)),
                    .action("Redo", "arrow.uturn.forward", .key(Key.z, [.command, .shift])),
                    .action("Find", "magnifyingglass", .key(Key.f, .command)),
                    .action("Comment", "text.bubble", .key(Key.slash, .command)),
                    .well("Nav", "ellipsis.circle", Halo(arc: arc(180), spokes: [
                        .action("Up", "arrow.up", .key(Key.up)),
                        .action("Down", "arrow.down", .key(Key.down)),
                        .action("Left", "arrow.left", .key(Key.left)),
                        .action("Right", "arrow.right", .key(Key.right)),
                    ])),
                ]))
    }
}
