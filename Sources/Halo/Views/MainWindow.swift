import SwiftUI
import AppKit

/// Halo's main window — a proper desktop app surface with a sidebar. Today it
/// hosts Setup (onboarding), General (settings) and About; the Wheels editor and
/// richer Voice settings grow into their panes next. The mouse-summoned wheel and
/// menu-bar glyph keep running in the background regardless of this window.
struct MainWindow: View {
    @Environment(HaloStore.self) private var store
    @Environment(Voice.self) private var voice
    @Environment(Permissions.self) private var permissions

    @State private var section: HaloSection? = .setup

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(HaloSection.allCases) { s in
                    Label(s.title, systemImage: s.icon).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 178, ideal: 198, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AmbientBackground())
        }
        .preferredColorScheme(.dark)
        .onAppear {
            section = permissions.allGranted ? .wheels : .setup
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }

    @ViewBuilder private var detail: some View {
        switch section ?? .setup {
        case .setup:
            OnboardingView(permissions: permissions, voice: voice, store: store,
                           onRelaunch: Self.relaunch,
                           onDone: { section = .wheels })
        case .wheels:
            WheelsEditor()
        case .voice:
            voicePane
        case .general:
            SettingsView()
        case .about:
            aboutPane
        }
    }

    // MARK: Panes

    /// Writes both config and the editor draft so an in-progress wheel edit's Save
    /// doesn't revert this setting.
    private var soundsBinding: Binding<Bool> {
        Binding(get: { store.config.sounds },
                set: { store.config.sounds = $0; store.draft.sounds = $0 })
    }

    private var voicePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Voice").font(.system(size: 24, weight: .semibold, design: .rounded))
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Dictation model")
                        Text(voice.statusText).font(.system(size: 13))
                        if case .downloading(let p) = voice.status {
                            ProgressView(value: p).tint(Color(red: 0.55, green: 0.50, blue: 0.98))
                        }
                    }
                }
                Card {
                    Toggle(isOn: soundsBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interface sounds").font(.system(size: 13, weight: .semibold))
                            Text("Soft cues on summon, select, fire, and send.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                Card {
                    Text("Voice options (the finish ring and dictation verbs) live in config.yaml for now — see General → Reveal in Finder. Toggles land here alongside the wheel editor.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(28)
        }
    }

    private var aboutPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halo").font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("Version \(Self.version) · by tinkerhaus").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A mouse-summoned radial command wheel with on-device voice dictation.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("Star on GitHub ⭐") { open("https://github.com/tinkerhaus/halo") }
                                .buttonStyle(.borderedProminent)
                            Button("View source") { open("https://github.com/tinkerhaus/halo") }
                                .buttonStyle(.bordered)
                        }
                        Text("Free & source-available under the PolyForm Noncommercial License — use it freely for non-commercial purposes.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(28)
        }
    }

    private func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Relaunch the app so freshly-granted TCC permissions take effect.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

enum HaloSection: String, CaseIterable, Identifiable, Hashable {
    case setup, wheels, voice, general, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .setup: return "Setup"
        case .wheels: return "Wheels"
        case .voice: return "Voice"
        case .general: return "General"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .setup: return "checklist"
        case .wheels: return "circle.dotted.circle"
        case .voice: return "mic.fill"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
