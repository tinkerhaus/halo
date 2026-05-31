import SwiftUI
import AppKit

/// Halo's settings. For now: how the wheel is summoned, and where its config
/// lives. The wheel editor (profiles, spokes, sounds, voice) lands next.
struct SettingsView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(HaloStore.self) private var store
    @State private var recorder = ButtonRecorder()

    var body: some View {
        @Bindable var prefs = prefs
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summonCard
                    configCard
                }
                .frame(maxWidth: 600)
                .padding(28)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "circle.dotted.circle").font(.system(size: 24, weight: .thin))
                Text("Halo").font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            Text("Hold your summon button anywhere, flick to a spoke, release to fire it.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var summonCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Summon")
                HStack {
                    Text("Button")
                    Spacer()
                    if recorder.isRecording {
                        Text("Click any mouse button…").foregroundStyle(.orange)
                        Button("Cancel") { recorder.stop() }.buttonStyle(.borderless)
                    } else {
                        Text(mouseButtonName(prefs.summonButton))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Button("Change") {
                            recorder.record { prefs.summonButton = $0 }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text("Halo needs Accessibility (to intercept the button and type keys) and Input Monitoring (to catch side buttons that mouse drivers remap). Grant both in System Settings → Privacy & Security, then quit and reopen Halo.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var configCard: some View {
        Card {
            HStack {
                Text("The wheel layout lives in an editable JSON file. Hand-edit it (or have an AI edit it); the next summon picks it up.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
