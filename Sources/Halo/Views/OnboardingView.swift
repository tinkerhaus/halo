import SwiftUI
import AppKit

/// First-run / setup checklist: grant the three permissions and watch the voice
/// model download — all live-updating, so granting in System Settings ticks the
/// row here without a relaunch.
struct OnboardingView: View {
    let permissions: Permissions
    let voice: Voice
    let store: HaloStore
    var onRelaunch: () -> Void
    var onDone: () -> Void

    @State private var recorder = ButtonRecorder()

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    permissionsCard
                    summonCard
                    modelCard
                    footer
                }
                .padding(28)
                .frame(maxWidth: 520)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HaloLogo(size: 52)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Welcome to Halo").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("by tinkerhaus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Text("Hold a mouse button anywhere to bloom the command wheel; release at its center to dictate. Pick your button, grant a couple of permissions, and you're set.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summonCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Summon button")
                HStack(spacing: 12) {
                    Image(systemName: "computermouse.fill").font(.system(size: 18)).frame(width: 24)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Held to open the wheel").font(.system(size: 13, weight: .semibold))
                        Text(recorder.isRecording ? "Click the button you want to use…"
                                                   : "Currently: \(mouseButtonName(store.summonButton))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if recorder.isRecording {
                        Button("Cancel") { recorder.stop() }.buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Button("Choose…") {
                            recorder.record {
                                store.summonButton = $0
                                NotificationCenter.default.post(name: .haloSummonButtonRecorded, object: nil)
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Text("Use a side/extra button if your mouse has one — otherwise the middle button (press the scroll wheel). Left and right clicks can't be used.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Permissions")
                    Spacer()
                    Button("Re-check") { permissions.refresh() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                permissionRow(.accessibility, title: "Accessibility", icon: "hand.raised.fill",
                              why: "Intercept the summon button and synthesize keystrokes.")
                divider
                permissionRow(.inputMonitoring, title: "Input Monitoring", icon: "computermouse.fill",
                              why: "Read mouse side buttons that drivers (e.g. Logitech) remap.")
                divider
                permissionRow(.microphone, title: "Microphone", icon: "mic.fill",
                              why: "Voice dictation — processed entirely on-device.")
            }
        }
    }

    private var divider: some View { Divider().overlay(.white.opacity(0.08)) }

    private func permissionRow(_ p: Permission, title: String, icon: String, why: String) -> some View {
        let ok = permissions.granted(p)
        return HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : icon)
                .font(.system(size: 18)).frame(width: 24)
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(why).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if ok {
                Text("Granted").font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
            } else {
                Button("Open Settings") { permissions.request(p) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Voice model")
                HStack(spacing: 12) {
                    Image(systemName: voice.isReady ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18)).frame(width: 24)
                        .foregroundStyle(voice.isReady ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On-device dictation model").font(.system(size: 13, weight: .semibold))
                        Text(voice.statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if case .downloading(let p) = voice.status {
                    ProgressView(value: p).tint(Color(red: 0.55, green: 0.50, blue: 0.98))
                }
                if let note = voice.preparingNote {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Downloads once (~1.5 GB) from Hugging Face, then stays cached. You can start using the wheel for keystrokes before it finishes; dictation lights up when it's ready.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Granted a permission but the box won't tick? Click Relaunch — macOS applies Accessibility & Input Monitoring to a fresh launch.",
                  systemImage: "arrow.clockwise.circle")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Still stuck? In System Settings remove Halo from the list (select it, press −) and add it back with + — a leftover entry from an old version can hold the grant.",
                  systemImage: "wrench.and.screwdriver")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if permissions.allGranted {
                HStack {
                    Button("Relaunch Halo", action: onRelaunch).buttonStyle(.bordered)
                    Spacer()
                    Button("Start using Halo", action: onDone).buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    Button("Relaunch Halo", action: onRelaunch).buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Continue", action: onDone).buttonStyle(.bordered)
                }
            }
        }
    }
}
