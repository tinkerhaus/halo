import SwiftUI
import AppKit

/// Halo's settings. For now: how the wheel is summoned, and where its config
/// lives. The wheel editor (profiles, spokes, sounds, voice) lands next.
struct SettingsView: View {
    @Environment(HaloStore.self) private var store
    @State private var recorder = ButtonRecorder()
    @State private var showResetConfirm = false

    var body: some View {
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
                HaloLogo(size: 28)
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
                        Text(mouseButtonName(store.summonButton))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Button("Change") {
                            recorder.record {
                                store.summonButton = $0
                                NotificationCenter.default.post(name: .haloSummonButtonRecorded, object: nil)
                            }
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Everything lives in an editable YAML file (config.yaml). Hand-edit it (or have an AI edit it); the next summon picks it up.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                    }
                    .buttonStyle(.bordered)
                }

                if let error = store.configError {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Config couldn't be parsed — using defaults until it's fixed.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))
                }

                HStack {
                    Spacer()
                    Button("Reset to Defaults…", role: .destructive) { showResetConfirm = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog("Reset Halo config to defaults?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset Config", role: .destructive) { store.resetToStarter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites config.yaml with the built-in defaults. Your current config will be lost.")
        }
    }
}
