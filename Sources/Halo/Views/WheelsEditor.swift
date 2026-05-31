import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Wheels editor — a canvas-primary editor for Halo's radial wheels. The
/// canvas renders the real wheel (same arc math, same look as when summoned); a
/// contextual inspector handles what you can't drag.
///
/// Edits mutate `store.draft`, a working copy — **nothing is written to
/// `config.yaml` until you Save** (`store.commitDraft()`). A header shows whether
/// there are unsaved changes. Every UI label still mirrors a literal config key.
///
/// Layout: `Targets rail | Canvas | Inspector`. A target is the `Default` wheel or
/// a `Profile`; the `Wheel | Finish` segment picks which of its two halos you edit;
/// a breadcrumb tracks well depth (drill into a well by double-clicking it).
struct WheelsEditor: View {
    @Environment(HaloStore.self) private var store

    @State private var target: EditorTarget = .default
    @State private var tab: HaloTab = .wheel
    @State private var wellPath: [Int] = []
    @State private var selection: CanvasSelection = .empty
    @State private var keyRecorder = KeystrokeRecorder()
    @State private var recordingRef: StepRef?
    @State private var pendingConvert: PendingConvert?
    @State private var pendingProfileDelete: UUID?
    @State private var pendingSpokeDelete: Int?
    @State private var pendingDiscard = false
    @State private var newBundleID = ""

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            HStack(spacing: 0) {
                targetsRail.frame(width: 208)
                verticalRule
                VStack(spacing: 0) {
                    topBar
                    canvasArea
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                verticalRule
                inspector.frame(width: 332)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: tab) { _, _ in wellPath = []; selection = .empty }
        .onChange(of: selection) { _, _ in cancelRecording() }
        .onDisappear { cancelRecording() }
        .confirmationDialog("Discard this spoke's contents?", isPresented: pendingConvertShown, titleVisibility: .visible) {
            Button(pendingConvert?.toWell == true ? "Convert to Well" : "Convert to Action", role: .destructive) {
                if let p = pendingConvert { setSpokeType(p.spoke, toWell: p.toWell) }
                pendingConvert = nil
            }
            Button("Cancel", role: .cancel) { pendingConvert = nil }
        } message: {
            Text(pendingConvert?.toWell == true
                 ? "The keystroke / steps on this spoke will be replaced by an empty sub-ring (well)."
                 : "The nested spokes inside this well will be removed.")
        }
        .confirmationDialog("Delete this profile?", isPresented: profileDeleteShown, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                if let id = pendingProfileDelete { deleteProfile(id) }
                pendingProfileDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingProfileDelete = nil }
        } message: {
            Text("This removes the profile and its wheel. It's final once you Save.")
        }
        .confirmationDialog("Delete this well?", isPresented: spokeDeleteShown, titleVisibility: .visible) {
            Button("Delete Well", role: .destructive) {
                if let i = pendingSpokeDelete { deleteSpoke(i) }
                pendingSpokeDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingSpokeDelete = nil }
        } message: {
            Text("This removes the well and every spoke nested inside it.")
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $pendingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                store.discardDraft()
                target = .default; tab = .wheel; wellPath = []; selection = .empty
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unsaved edits will revert to the last saved version.")
        }
    }

    private var pendingConvertShown: Binding<Bool> {
        Binding(get: { pendingConvert != nil }, set: { if !$0 { pendingConvert = nil } })
    }
    private var profileDeleteShown: Binding<Bool> {
        Binding(get: { pendingProfileDelete != nil }, set: { if !$0 { pendingProfileDelete = nil } })
    }
    private var spokeDeleteShown: Binding<Bool> {
        Binding(get: { pendingSpokeDelete != nil }, set: { if !$0 { pendingSpokeDelete = nil } })
    }

    /// Confirm before deleting a non-empty well (it takes its whole sub-ring with it);
    /// plain spokes delete straight away.
    private func requestDeleteSpoke(_ i: Int) {
        if case .opens(let h)? = currentHalo.spokes[safe: i]?.content, !h.spokes.isEmpty {
            pendingSpokeDelete = i
        } else {
            deleteSpoke(i)
        }
    }

    private var verticalRule: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(width: 1).frame(maxHeight: .infinity)
    }

    // MARK: - Header (save / discard / dirty state)

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Text("Wheels").font(.system(size: 15, weight: .semibold))
            dirtyBadge
            Spacer()
            Button("Discard") { pendingDiscard = true }
                .disabled(!store.hasUnsavedChanges)
            Button { store.commitDraft() } label: {
                Label("Save", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!store.hasUnsavedChanges)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var dirtyBadge: some View {
        if store.hasUnsavedChanges {
            HStack(spacing: 6) {
                Circle().fill(.orange).frame(width: 7, height: 7)
                Text("Unsaved changes").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(.orange.opacity(0.14)))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green.opacity(0.75))
                Text("Saved").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Targets rail

    private var targetsRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            railHeader("Wheels")
            targetRow("Default", icon: "circle.dashed", subtitle: "no match", t: .default)
            ForEach(store.draft.profiles) { p in
                targetRow(p.name.isEmpty ? "Untitled" : p.name, icon: "square.stack.3d.up.fill",
                          subtitle: appCount(p.appBundleIDs.count), t: .profile(p.id))
            }
            Menu {
                Button("Blank profile") {
                    addProfile(name: "New Profile",
                               halo: Halo(arc: Arc(spanDegrees: 200, centerDegrees: -90), radius: 124, spokes: []),
                               finish: nil)
                }
                Section("Start from a copy of") {
                    Button("Default") { addProfile(name: "Default copy", halo: store.draft.defaultHalo, finish: nil) }
                    ForEach(store.draft.profiles) { p in
                        Button(p.name.isEmpty ? "Untitled" : p.name) {
                            addProfile(name: "\(p.name.isEmpty ? "Profile" : p.name) copy", halo: p.halo, finish: p.finish)
                        }
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus").font(.system(size: 11)).frame(width: 18)
                    Text("Add profile…").font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9).padding(.vertical, 7).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).foregroundStyle(.secondary)

            Spacer()
            railHeader("Summon")
            HStack(spacing: 9) {
                Image(systemName: "computermouse.fill").font(.system(size: 11)).frame(width: 18)
                Text(mouseButtonName(store.config.summonButton)).font(.system(size: 12))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
        }
        .padding(.horizontal, 10).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.18))
    }

    private func railHeader(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8)
            .foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 2)
    }

    private func targetRow(_ title: String, icon: String, subtitle: String, t: EditorTarget) -> some View {
        let isSel = target == t
        return Button {
            target = t; tab = .wheel; wellPath = []; selection = .empty
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSel ? AnyShapeStyle(HaloPalette.accent.opacity(0.22)) : AnyShapeStyle(Color.clear)))
            .foregroundStyle(isSel ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appCount(_ n: Int) -> String { n == 0 ? "no apps" : "\(n) app\(n == 1 ? "" : "s")" }

    // MARK: - Top bar (breadcrumb + Wheel|Finish segment)

    private var topBar: some View {
        HStack(spacing: 14) {
            breadcrumb
            Spacer()
            Picker("", selection: $tab) {
                Text("Wheel").tag(HaloTab.wheel)
                Text("Finish ring").tag(HaloTab.finish)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { } label: { Label("Test", systemImage: "play.fill") }
                .controlSize(.small).disabled(true)
                .help("Summon this wheel on screen — coming soon.")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text(targetName).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(wellPath.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .onTapGesture { wellPath = []; selection = .empty }
            ForEach(Array(wellLabels.enumerated()), id: \.offset) { i, label in
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Text(label).font(.system(size: 14, weight: i == wellLabels.count - 1 ? .semibold : .regular))
                    .foregroundStyle(i == wellLabels.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .onTapGesture { wellPath = Array(wellPath.prefix(i + 1)); selection = .empty }
            }
        }
    }

    private var targetName: String {
        switch target {
        case .default: return "Default"
        case .profile(let id): return store.draft.profiles.first { $0.id == id }?.name ?? "Profile"
        }
    }

    /// Labels of the wells we've drilled into, in order — drives the breadcrumb.
    private var wellLabels: [String] {
        var labels: [String] = []
        var halo = baseHalo(in: store.draft)
        for idx in wellPath {
            guard halo.spokes.indices.contains(idx), case .opens(let child) = halo.spokes[idx].content else { break }
            labels.append(halo.spokes[idx].label)
            halo = child
        }
        return labels
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        ZStack {
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { selection = .empty }
            WheelCanvas(halo: currentHalo, selection: selection, centerHint: centerHint,
                        onSelect: { selection = $0 },
                        onDrill: { drillInto($0) },
                        onReorder: { from, to in reorderSpoke(from, to) },
                        onSetSpan: { setSpan($0) },
                        onSetCenter: { setCenter($0) })
            VStack {
                Spacer()
                addSpokeControl.padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The add-spoke affordance — deliberately *off* the ring, below the wheel. At
    /// the cap it turns into a notice (nest a well to go further).
    @ViewBuilder private var addSpokeControl: some View {
        if currentHalo.spokes.count < effectiveMaxSpokes {
            Button { addSpoke() } label: { Label("Add spoke", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Label("Max \(effectiveMaxSpokes) spokes — nest a well to add more", systemImage: "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.orange.opacity(0.12)))
        }
    }

    /// A well reserves one slot for the auto Back spoke, so it holds one fewer.
    private var effectiveMaxSpokes: Int { wellPath.isEmpty ? Halo.maxSpokes : Halo.maxSpokes - 1 }

    private func drillInto(_ index: Int) {
        guard currentHalo.spokes.indices.contains(index), currentHalo.spokes[index].isWell else { return }
        wellPath.append(index)
        selection = .empty
    }

    /// Icon + label for the hub, matching the runtime's center semantics.
    private var centerHint: (icon: String, label: String) {
        if tab == .finish { return ("paperplane.fill", "Release to send") }
        return ("mic.fill", "Release to dictate")     // center always dictates, every depth
    }

    // MARK: - Inspector

    @ViewBuilder private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selection {
                case .empty:        haloInspector
                case .spoke(let i): spokeInspector(i)
                case .center:       centerInspector
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.black.opacity(0.12))
    }

    // Halo-level properties (nothing selected).
    @ViewBuilder private var haloInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            inspectorKicker(tab == .finish ? "Finish ring" : "Wheel", title: targetName)

            if isInheritedFinish {
                inheritedFinishCard
            } else {
                if wellPath.isEmpty {
                    labeled("Arc span") { sliderRow(value: spanBinding, range: 0...Double(Arc.maxSpanDegrees), suffix: "°") }
                    labeled("Arc center") { sliderRow(value: centerBinding, range: -180...180, suffix: "°") }
                    labeled("Radius") { sliderRow(value: radiusBinding, range: 80...210, suffix: "") }
                } else {
                    Text("This well's sub-ring reuses the parent wheel's shape — its spoke becomes ⟵ Back here — so it has no separate arc or radius. The center always dictates.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Spokes").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(currentHalo.spokes.count) / \(effectiveMaxSpokes)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }

                if tab == .finish, case .profile = target {
                    Button(role: .destructive) { revertFinish() } label: {
                        Label("Revert to default finish ring", systemImage: "arrow.uturn.backward")
                    }.controlSize(.small)
                }

                if tab == .wheel, wellPath.isEmpty, case .profile(let id) = target {
                    profileCard(id)
                }

                Text("Click a spoke to edit it, the hub for its center action, drag a spoke to reorder, or drag the ◇ handles to reshape the arc.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// True when a profile's Finish tab is showing but it has no override (it inherits
    /// the global default finish ring) — we prompt to override instead of editing.
    private var isInheritedFinish: Bool {
        guard tab == .finish, case .profile(let id) = target else { return false }
        return store.draft.profiles.first { $0.id == id }?.finish == nil
    }

    private var inheritedFinishCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This profile uses the global default finish ring.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { overrideFinish() } label: { Label("Override for this profile", systemImage: "plus.circle") }
                .controlSize(.small)
            Text("Edit the default itself under Default → Finish ring.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, fallback: AnyShapeStyle(.white.opacity(0.035)))
    }

    private func profileCard(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Profile")
            labeled("Name") {
                TextField("Name", text: renameBinding(id)).textFieldStyle(.plain)
                    .font(.system(size: 13)).padding(7).background(fieldBG)
            }
            appsEditor(id, store.draft.profiles.first { $0.id == id }?.appBundleIDs ?? [])
            Button(role: .destructive) { pendingProfileDelete = id } label: {
                Label("Delete profile", systemImage: "trash")
            }.controlSize(.small)
        }
    }

    private func appsEditor(_ id: UUID, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Apps")
            ForEach(ids, id: \.self) { bid in
                let info = appInfo(bid)
                HStack(spacing: 8) {
                    if let icon = info.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 18).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(info.name).font(.system(size: 12)).lineLimit(1)
                        Text(bid).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button { removeApp(id, bundleID: bid) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            if ids.isEmpty {
                Text("No apps — this profile won't match anything yet.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(runningApps(), id: \.id) { app in Button(app.name) { addApp(id, bundleID: app.id) } }
                } label: { Label("Running app", systemImage: "plus") }.fixedSize()
                Button { chooseAppFile(id) } label: { Label("Choose…", systemImage: "folder") }
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                TextField("com.example.app", text: $newBundleID).textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced)).padding(5).background(fieldBG)
                Button("Add") { addApp(id, bundleID: newBundleID); newBundleID = "" }
                    .controlSize(.small).disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, fallback: AnyShapeStyle(.white.opacity(0.035)))
    }

    // Spoke properties.
    @ViewBuilder private func spokeInspector(_ i: Int) -> some View {
        if currentHalo.spokes.indices.contains(i) {
            let spoke = currentHalo.spokes[i]
            VStack(alignment: .leading, spacing: 16) {
                inspectorKicker("Spoke", title: spoke.label.isEmpty ? "Untitled" : spoke.label)

                labeled("Label") {
                    TextField("Label", text: labelBinding(i)).textFieldStyle(.plain)
                        .font(.system(size: 13)).padding(7).background(fieldBG)
                }
                labeled("Glyph · SF Symbol") {
                    GlyphPicker(glyph: glyphBinding(i))
                }
                labeled("Type") {
                    Picker("", selection: typeBinding(i)) {
                        Text("Action").tag(false)
                        Text("Well").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                if spoke.isWell {
                    wellCard(i, spoke)
                } else if case .performs(let action) = spoke.content {
                    actionEditor(i, action)
                }

                Button(role: .destructive) { requestDeleteSpoke(i) } label: {
                    Label("Delete spoke", systemImage: "trash")
                }.controlSize(.small)
            }
        } else {
            Color.clear.onAppear { selection = .empty }
        }
    }

    private var centerInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorKicker("Center · release-at-hub", title: centerHint.label)
            Text(centerExplanation).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var centerExplanation: String {
        if tab == .finish { return "A finish ring sends the dictated text when you release at center." }
        return "Releasing at center always starts a dictation session — on the wheel and inside every well. To leave a well, dwell on its ⟵ Back spoke."
    }

    // MARK: - Inspector building blocks

    private func inspectorKicker(_ kicker: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1)
        }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            content()
        }
    }

    private func sliderRow(value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue.rounded()))\(suffix)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var fieldBG: some View {
        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Action / step editor

    private func wellCard(_ i: Int, _ spoke: Spoke) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Well")
            Text(actionSummary(spoke)).font(.system(size: 12)).foregroundStyle(.secondary)
            Button { drillInto(i) } label: {
                Label("Edit well contents", systemImage: "arrow.down.right.circle")
            }.controlSize(.small)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, fallback: AnyShapeStyle(.white.opacity(0.035)))
    }

    private func actionEditor(_ i: Int, _ action: Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Action")
                Spacer()
                Text("\(action.steps.count) step\(action.steps.count == 1 ? "" : "s")")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if action.steps.isEmpty {
                Text("No steps yet — add one below.").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            ForEach(Array(action.steps.enumerated()), id: \.offset) { j, s in
                stepRow(i, j, s, count: action.steps.count)
            }
            addStepMenu(i)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, fallback: AnyShapeStyle(.white.opacity(0.035)))
    }

    private func stepRow(_ i: Int, _ j: Int, _ s: Step, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(stepKind(s)).font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.tertiary).frame(width: 36, alignment: .leading)
            stepValueEditor(i, j, s)
            Spacer(minLength: 4)
            Button { moveStep(i, j, -1) } label: { Image(systemName: "chevron.up") }.disabled(j == 0)
            Button { moveStep(i, j, +1) } label: { Image(systemName: "chevron.down") }.disabled(j == count - 1)
            Button { removeStep(i, j) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
        }
        .buttonStyle(.borderless).font(.system(size: 11))
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
    }

    @ViewBuilder private func stepValueEditor(_ i: Int, _ j: Int, _ s: Step) -> some View {
        switch s {
        case let .key(code, mods):
            keyStepEditor(i, j, code: code, mods: mods)
        case .text:
            TextField("text to type", text: stepTextBinding(i, j)).textFieldStyle(.plain)
                .font(.system(size: 12)).padding(5).background(fieldBG)
        case .paste:
            Stepper(value: pasteBinding(i, j), in: 0...20) {
                Text("clipboard #\(pasteBinding(i, j).wrappedValue)").font(.system(size: 12))
            }
        case .pause:
            HStack(spacing: 4) {
                TextField("", value: pauseBinding(i, j), format: .number).textFieldStyle(.plain)
                    .frame(width: 52).padding(5).background(fieldBG)
                    .font(.system(size: 12, design: .monospaced))
                Text("ms").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .verb:
            Picker("", selection: verbBinding(i, j)) {
                ForEach(Verb.allCases, id: \.self) { v in Text("do: \(v.rawValue)").tag(v) }
            }.labelsHidden().fixedSize()
        case .bash:
            VStack(alignment: .leading, spacing: 5) {
                TextField("shell — $HALO_TRANSCRIPT = dictation, $name = a saved output", text: bashCommandBinding(i, j))
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).padding(5).background(fieldBG)
                HStack(spacing: 8) {
                    Text("as $").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    TextField("name", text: bashNameBinding(i, j))
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                        .padding(4).background(fieldBG).frame(width: 84)
                    Toggle("Inject output", isOn: bashInjectBinding(i, j))
                        .toggleStyle(.checkbox).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func keyStepEditor(_ i: Int, _ j: Int, code: UInt16, mods: Modifiers) -> some View {
        if isRecording(i, j) {
            HStack(spacing: 8) {
                Text("Press a key…").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                Button("Cancel") { cancelRecording() }.controlSize(.small)
            }
        } else {
            HStack(spacing: 8) {
                Text(KeyChord.format(code: code, modifiers: mods))
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.50, blue: 0.98).opacity(0.16)))
                    .overlay(Capsule().strokeBorder(Color(red: 0.55, green: 0.50, blue: 0.98).opacity(0.4)))
                Button("Record") { startRecording(i, j) }.controlSize(.small)
            }
        }
    }

    private func addStepMenu(_ i: Int) -> some View {
        Menu {
            Button("Key") { addStep(i, .key(code: Key.enter, modifiers: [])) }
            Button("Text") { addStep(i, .text("")) }
            Button("Bash") { addStep(i, .bash(command: "", inject: false, name: nil)) }
            Button("Paste") { addStep(i, .paste(recent: 0)) }
            Button("Pause") { addStep(i, .pause(milliseconds: 200)) }
            Menu("Verb") {
                ForEach(Verb.allCases, id: \.self) { v in Button("do: \(v.rawValue)") { addStep(i, .verb(v)) } }
            }
        } label: { Label("Add step", systemImage: "plus") }
        .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
    }

    private func stepKind(_ s: Step) -> String {
        switch s {
        case .key:   return "KEY"
        case .text:  return "TEXT"
        case .paste: return "PASTE"
        case .pause: return "PAUSE"
        case .verb:  return "DO"
        case .bash:  return "BASH"
        }
    }

    private func isRecording(_ i: Int, _ j: Int) -> Bool { recordingRef == StepRef(spoke: i, step: j) }
    private func startRecording(_ i: Int, _ j: Int) {
        recordingRef = StepRef(spoke: i, step: j)
        keyRecorder.record { code, mods in
            setStep(i, j, .key(code: code, modifiers: mods))
            recordingRef = nil
        }
    }
    private func cancelRecording() { keyRecorder.stop(); recordingRef = nil }

    private func mutateSpokeAction(_ i: Int, _ transform: (inout [Step]) -> Void) {
        mutateHalo { h in
            guard h.spokes.indices.contains(i), case .performs(var a) = h.spokes[i].content else { return }
            transform(&a.steps)
            h.spokes[i].content = .performs(a)
        }
    }
    private func setStep(_ i: Int, _ j: Int, _ s: Step) { mutateSpokeAction(i) { if $0.indices.contains(j) { $0[j] = s } } }
    private func addStep(_ i: Int, _ s: Step) { mutateSpokeAction(i) { $0.append(s) } }
    private func removeStep(_ i: Int, _ j: Int) { mutateSpokeAction(i) { if $0.indices.contains(j) { $0.remove(at: j) } } }
    private func moveStep(_ i: Int, _ j: Int, _ delta: Int) {
        mutateSpokeAction(i) { steps in
            let k = j + delta
            guard steps.indices.contains(j), steps.indices.contains(k) else { return }
            steps.swapAt(j, k)
        }
    }

    private func step(_ i: Int, _ j: Int) -> Step? {
        guard case .performs(let a)? = currentHalo.spokes[safe: i]?.content else { return nil }
        return a.steps[safe: j]
    }
    private func stepTextBinding(_ i: Int, _ j: Int) -> Binding<String> {
        Binding(get: { if case .text(let t)? = step(i, j) { return t }; return "" },
                set: { setStep(i, j, .text($0)) })
    }
    private func pasteBinding(_ i: Int, _ j: Int) -> Binding<Int> {
        Binding(get: { if case .paste(let r)? = step(i, j) { return r }; return 0 },
                set: { setStep(i, j, .paste(recent: $0)) })
    }
    private func pauseBinding(_ i: Int, _ j: Int) -> Binding<Int> {
        Binding(get: { if case .pause(let ms)? = step(i, j) { return ms }; return 0 },
                set: { setStep(i, j, .pause(milliseconds: $0)) })
    }
    private func verbBinding(_ i: Int, _ j: Int) -> Binding<Verb> {
        Binding(get: { if case .verb(let v)? = step(i, j) { return v }; return .send },
                set: { setStep(i, j, .verb($0)) })
    }
    private func bashCommandBinding(_ i: Int, _ j: Int) -> Binding<String> {
        Binding(get: { if case .bash(let c, _, _)? = step(i, j) { return c }; return "" },
                set: { v in if case .bash(_, let inject, let name)? = step(i, j) { setStep(i, j, .bash(command: v, inject: inject, name: name)) } })
    }
    private func bashInjectBinding(_ i: Int, _ j: Int) -> Binding<Bool> {
        Binding(get: { if case .bash(_, let inject, _)? = step(i, j) { return inject }; return false },
                set: { v in if case .bash(let c, _, let name)? = step(i, j) { setStep(i, j, .bash(command: c, inject: v, name: name)) } })
    }
    private func bashNameBinding(_ i: Int, _ j: Int) -> Binding<String> {
        Binding(get: { if case .bash(_, _, let name)? = step(i, j) { return name ?? "" }; return "" },
                set: { v in
                    if case .bash(let c, let inject, _)? = step(i, j) {
                        let trimmed = v.trimmingCharacters(in: .whitespaces)
                        setStep(i, j, .bash(command: c, inject: inject, name: trimmed.isEmpty ? nil : trimmed))
                    }
                })
    }

    // MARK: - Summaries

    private func actionSummary(_ spoke: Spoke) -> String {
        switch spoke.content {
        case .opens(let h): return "\(h.spokes.count) spoke\(h.spokes.count == 1 ? "" : "s") inside"
        case .performs(let a):
            return a.steps.isEmpty ? "No action" : a.steps.map(stepLabel).joined(separator: " → ")
        }
    }

    private func stepLabel(_ s: Step) -> String {
        switch s {
        case .key(let code, let mods): return KeyChord.format(code: code, modifiers: mods)
        case .text(let t):             return "“\(t.prefix(18))”"
        case .paste(let r):            return "paste \(r)"
        case .pause(let ms):           return "pause \(ms)ms"
        case .verb(let v):             return "do:\(v.rawValue)"
        case .bash(let c, _, let n):
            let cmd = c.isEmpty ? "…" : String(c.prefix(18))
            return n.map { "$ \(cmd) → $\($0)" } ?? "$ \(cmd)"
        }
    }

    // MARK: - Action ⇄ Well conversion

    private func typeBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: { currentHalo.spokes[safe: i]?.isWell ?? false },
                set: { requestConvert(i, toWell: $0) })
    }

    /// Switch a spoke between Action and Well. If the switch would throw away
    /// non-empty content (steps, or nested spokes), confirm first.
    private func requestConvert(_ i: Int, toWell: Bool) {
        guard let spoke = currentHalo.spokes[safe: i], spoke.isWell != toWell else { return }
        let discards: Bool
        switch spoke.content {
        case .performs(let a): discards = toWell && !a.steps.isEmpty
        case .opens(let h):    discards = !toWell && !h.spokes.isEmpty
        }
        if discards { pendingConvert = PendingConvert(spoke: i, toWell: toWell) }
        else { setSpokeType(i, toWell: toWell) }
    }

    private func setSpokeType(_ i: Int, toWell: Bool) {
        mutateHalo { h in
            guard h.spokes.indices.contains(i) else { return }
            if toWell {
                if case .performs = h.spokes[i].content { h.spokes[i].content = .opens(Halo()) }
            } else {
                if case .opens = h.spokes[i].content {
                    h.spokes[i].content = .performs(Action([.key(code: Key.enter, modifiers: [])]))
                }
            }
        }
    }

    // MARK: - Spatial edits (driven by the canvas) & spoke add/delete

    private func reorderSpoke(_ from: Int, _ to: Int) {
        mutateHalo { h in
            guard h.spokes.indices.contains(from) else { return }
            let s = h.spokes.remove(at: from)
            h.spokes.insert(s, at: min(max(to, 0), h.spokes.count))
        }
        if case .spoke(from) = selection { selection = .spoke(to) }
    }
    private func setSpan(_ v: Int) { mutateHalo { $0.arc.spanDegrees = v } }
    private func setCenter(_ v: Int) { mutateHalo { $0.arc.centerDegrees = v } }

    private func addSpoke() {
        guard currentHalo.spokes.count < effectiveMaxSpokes else { return }
        let newIndex = currentHalo.spokes.count
        mutateHalo { $0.spokes.append(Spoke(label: "New", glyph: "circle",
                                            content: .performs(Action([.key(code: Key.enter, modifiers: [])])))) }
        selection = .spoke(newIndex)
    }
    private func deleteSpoke(_ i: Int) {
        mutateHalo { if $0.spokes.indices.contains(i) { $0.spokes.remove(at: i) } }
        selection = .empty
    }

    // MARK: - Profiles, apps & finish rings

    /// Append a profile (blank, or copied from Default / another profile). The copy
    /// starts with **no apps** so it won't fight the source for the same frontmost app.
    private func addProfile(name: String, halo: Halo, finish: Halo?) {
        let new = Profile(name: name, appBundleIDs: [], halo: halo, finish: finish)
        var cfg = store.draft
        cfg.profiles.append(new)
        store.draft = cfg
        target = .profile(new.id); tab = .wheel; wellPath = []; selection = .empty
    }

    private func deleteProfile(_ id: UUID) {
        var cfg = store.draft
        cfg.profiles.removeAll { $0.id == id }
        store.draft = cfg
        target = .default; tab = .wheel; wellPath = []; selection = .empty
    }

    private func renameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { store.draft.profiles.first { $0.id == id }?.name ?? "" },
                set: { v in
                    var cfg = store.draft
                    if let i = cfg.profiles.firstIndex(where: { $0.id == id }) { cfg.profiles[i].name = v }
                    store.draft = cfg
                })
    }

    private func addApp(_ id: UUID, bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var cfg = store.draft
        if let i = cfg.profiles.firstIndex(where: { $0.id == id }), !cfg.profiles[i].appBundleIDs.contains(trimmed) {
            cfg.profiles[i].appBundleIDs.append(trimmed)
            store.draft = cfg
        }
    }

    private func removeApp(_ id: UUID, bundleID: String) {
        var cfg = store.draft
        if let i = cfg.profiles.firstIndex(where: { $0.id == id }) {
            cfg.profiles[i].appBundleIDs.removeAll { $0 == bundleID }
            store.draft = cfg
        }
    }

    /// Apps currently running (regular, foreground-capable) — the quick-add menu.
    private func runningApps() -> [(name: String, id: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, id: String)? in
                guard let bid = app.bundleIdentifier, seen.insert(bid).inserted else { return nil }
                return (app.localizedName ?? bid, bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseAppFile(_ id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let bid = Bundle(url: url)?.bundleIdentifier {
            addApp(id, bundleID: bid)
        }
    }

    /// Resolve a bundle ID to an installed app's display name + icon (best effort).
    private func appInfo(_ bundleID: String) -> (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return (bundleID, nil) }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }

    private func overrideFinish() {
        guard case .profile(let id) = target else { return }
        let inherited = store.draft.voice.finish ?? HaloConfig.defaultFinish()
        var cfg = store.draft
        if let i = cfg.profiles.firstIndex(where: { $0.id == id }) { cfg.profiles[i].finish = inherited }
        store.draft = cfg
        selection = .empty
    }

    private func revertFinish() {
        guard case .profile(let id) = target else { return }
        var cfg = store.draft
        if let i = cfg.profiles.firstIndex(where: { $0.id == id }) { cfg.profiles[i].finish = nil }
        store.draft = cfg
        selection = .empty
    }

    // MARK: - Config resolution (the editor's read/write path into store.draft)

    /// The top halo for the current target + tab (before drilling into wells).
    private func baseHalo(in cfg: HaloConfig) -> Halo {
        switch target {
        case .default:
            return tab == .wheel ? cfg.defaultHalo : (cfg.voice.finish ?? HaloConfig.defaultFinish())
        case .profile(let id):
            guard let p = cfg.profiles.first(where: { $0.id == id }) else { return Halo() }
            return tab == .wheel ? p.halo : (p.finish ?? cfg.voice.finish ?? HaloConfig.defaultFinish())
        }
    }

    private func writeBaseHalo(_ base: Halo, in cfg: inout HaloConfig) {
        switch target {
        case .default:
            if tab == .wheel { cfg.defaultHalo = base } else { cfg.voice.finish = base }
        case .profile(let id):
            guard let i = cfg.profiles.firstIndex(where: { $0.id == id }) else { return }
            if tab == .wheel { cfg.profiles[i].halo = base } else { cfg.profiles[i].finish = base }
        }
    }

    /// The halo currently on the canvas — base walked down the well path.
    private func resolveHalo(in cfg: HaloConfig) -> Halo {
        var halo = baseHalo(in: cfg)
        for idx in wellPath {
            guard halo.spokes.indices.contains(idx), case .opens(let child) = halo.spokes[idx].content else { break }
            halo = child
        }
        return halo
    }

    private var currentHalo: Halo { resolveHalo(in: store.draft) }

    /// Replace the halo at `path` (relative to `halo`) with `newHalo`, in place.
    private func replaceHalo(in halo: inout Halo, path: ArraySlice<Int>, with newHalo: Halo) {
        guard let first = path.first else { halo = newHalo; return }
        guard halo.spokes.indices.contains(first), case .opens(var child) = halo.spokes[first].content else { return }
        replaceHalo(in: &child, path: path.dropFirst(), with: newHalo)
        halo.spokes[first].content = .opens(child)
    }

    /// Mutate the halo on the canvas and write it back into `store.draft` (no disk
    /// write — that only happens on Save / `commitDraft`).
    private func mutateHalo(_ transform: (inout Halo) -> Void) {
        var cfg = store.draft
        var cur = resolveHalo(in: cfg)
        transform(&cur)
        var base = baseHalo(in: cfg)
        replaceHalo(in: &base, path: wellPath[...], with: cur)
        writeBaseHalo(base, in: &cfg)
        store.draft = cfg
    }

    // MARK: - Bindings

    private func labelBinding(_ i: Int) -> Binding<String> {
        Binding(get: { currentHalo.spokes[safe: i]?.label ?? "" },
                set: { v in mutateHalo { if $0.spokes.indices.contains(i) { $0.spokes[i].label = v } } })
    }
    private func glyphBinding(_ i: Int) -> Binding<String> {
        Binding(get: { currentHalo.spokes[safe: i]?.glyph ?? "" },
                set: { v in mutateHalo { if $0.spokes.indices.contains(i) { $0.spokes[i].glyph = v } } })
    }
    private var spanBinding: Binding<Double> {
        Binding(get: { Double(currentHalo.arc.spanDegrees) },
                set: { v in mutateHalo { $0.arc.spanDegrees = Int(v.rounded()) } })
    }
    private var centerBinding: Binding<Double> {
        Binding(get: { Double(currentHalo.arc.centerDegrees) },
                set: { v in mutateHalo { $0.arc.centerDegrees = Int(v.rounded()) } })
    }
    private var radiusBinding: Binding<Double> {
        Binding(get: { Double(currentHalo.radius) },
                set: { v in mutateHalo { $0.radius = Int(v.rounded()) } })
    }
}

// MARK: - Editor state types

enum EditorTarget: Hashable {
    case `default`
    case profile(UUID)
}

enum HaloTab: Hashable { case wheel, finish }

enum CanvasSelection: Hashable {
    case empty
    case spoke(Int)
    case center
}

/// Identifies which step's key field is currently being recorded.
struct StepRef: Equatable { var spoke: Int; var step: Int }

/// A pending Action⇄Well conversion awaiting confirmation (it would discard content).
struct PendingConvert: Equatable { var spoke: Int; var toWell: Bool }

// MARK: - Shared palette (matches WheelView so the editor and the live wheel agree)

enum HaloPalette {
    static let accent = LinearGradient(
        colors: [Color(red: 0.55, green: 0.50, blue: 0.98), Color(red: 0.40, green: 0.72, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let spokeFill = Color(red: 0.14, green: 0.15, blue: 0.19)
    static let hubFill = Color(red: 0.10, green: 0.11, blue: 0.15)
}

// MARK: - WheelCanvas — a faithful, selectable render of one Halo

/// Renders a `Halo` exactly as it appears when summoned (same arc math, same
/// chips), but interactive: click a spoke or the hub to select; double-click a well
/// to drill in; drag a spoke to reorder; drag the ◇ handles to reshape the arc.
struct WheelCanvas: View {
    let halo: Halo
    var selection: CanvasSelection = .empty
    var centerHint: (icon: String, label: String) = ("mic.fill", "Release to dictate")
    var onSelect: (CanvasSelection) -> Void = { _ in }
    var onDrill: (Int) -> Void = { _ in }
    var onReorder: (Int, Int) -> Void = { _, _ in }
    var onSetSpan: (Int) -> Void = { _ in }
    var onSetCenter: (Int) -> Void = { _ in }

    private let space = "wheel"

    var body: some View {
        GeometryReader { geo in
            let layout = WheelLayout(halo: halo, size: geo.size)
            ZStack {
                ForEach(Array(halo.spokes.enumerated()), id: \.element.id) { i, spoke in
                    spokeChip(spoke, hot: selection == .spoke(i), scale: layout.scale)
                        .position(layout.position(i))
                        .onTapGesture(count: 2) { if spoke.isWell { onDrill(i) } }
                        .onTapGesture { onSelect(.spoke(i)) }
                        .gesture(spokeDrag(spoke.id, layout))
                }
                hub(scale: layout.scale)
                    .position(layout.center)
                    .onTapGesture { onSelect(.center) }
                if selection == .empty, !halo.spokes.isEmpty { arcHandles(layout) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: space)
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: selection)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: halo)
        }
    }

    // MARK: Gestures

    private func spokeDrag(_ id: UUID, _ layout: WheelLayout) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
            .onChanged { value in
                let ang = angleDeg(value.location, layout.center)
                let slot = nearestSlot(ang)
                if let cur = halo.spokes.firstIndex(where: { $0.id == id }), cur != slot {
                    onReorder(cur, slot)
                }
            }
    }

    private func spanDrag(_ layout: WheelLayout) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { value in
                let ang = angleDeg(value.location, layout.center)
                let half = abs(Arc.delta(.degrees(ang), halo.arc.center))
                onSetSpan(min(max(Int((half * 2).rounded()), 0), Arc.maxSpanDegrees))
            }
    }

    private func rotateDrag(_ layout: WheelLayout) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { value in onSetCenter(Int(angleDeg(value.location, layout.center).rounded())) }
    }

    private func angleDeg(_ p: CGPoint, _ center: CGPoint) -> Double {
        Double(atan2(p.y - center.y, p.x - center.x)) * 180 / .pi
    }
    private func nearestSlot(_ angDeg: Double) -> Int {
        let places = halo.arc.placements(count: halo.spokes.count)
        guard !places.isEmpty else { return 0 }
        var best = 0; var bd = Double.greatestFiniteMagnitude
        for (i, a) in places.enumerated() {
            let d = abs(Arc.delta(.degrees(angDeg), a))
            if d < bd { bd = d; best = i }
        }
        return best
    }
    private func point(_ r: CGFloat, _ deg: Double, _ center: CGPoint) -> CGPoint {
        let t = deg * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(cos(t)), y: center.y + r * CGFloat(sin(t)))
    }

    // MARK: Handles

    @ViewBuilder private func arcHandles(_ layout: WheelLayout) -> some View {
        let cDeg = Double(halo.arc.centerDegrees)
        let span = Double(min(max(halo.arc.spanDegrees, 0), Arc.maxSpanDegrees))
        let r = layout.radius + 34 * layout.scale
        Group {
            diamondHandle().position(point(r, cDeg - span / 2, layout.center)).gesture(spanDrag(layout))
            diamondHandle().position(point(r, cDeg + span / 2, layout.center)).gesture(spanDrag(layout))
            rotateKnob().position(point(r, cDeg, layout.center)).gesture(rotateDrag(layout))
        }
    }
    private func diamondHandle() -> some View {
        RoundedRectangle(cornerRadius: 2).fill(HaloPalette.hubFill)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(HaloPalette.accent, lineWidth: 2))
            .frame(width: 13, height: 13).rotationEffect(.degrees(45))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            .contentShape(Rectangle())
    }
    private func rotateKnob() -> some View {
        Circle().fill(HaloPalette.hubFill)
            .overlay(Circle().strokeBorder(HaloPalette.accent, lineWidth: 2))
            .overlay(Circle().fill(Color(red: 0.55, green: 0.50, blue: 0.98)).frame(width: 5, height: 5))
            .frame(width: 15, height: 15)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            .contentShape(Circle())
    }

    // MARK: Chips & hub

    private func spokeChip(_ spoke: Spoke, hot: Bool, scale: CGFloat) -> some View {
        let size = 64 * scale
        return VStack(spacing: 3 * scale) {
            Image(systemName: validGlyph(spoke.glyph)).font(.system(size: 18 * scale, weight: .semibold))
            Text(spoke.label).font(.system(size: 9.5 * scale, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(hot ? AnyShapeStyle(HaloPalette.accent) : AnyShapeStyle(HaloPalette.spokeFill)))
        .overlay(Circle().strokeBorder(.white.opacity(spoke.isWell ? 0.30 : 0), lineWidth: 1).padding(-3.5 * scale))
        .shadow(color: .black.opacity(0.45), radius: hot ? 12 : 6, y: 3)
        .scaleEffect(hot ? 1.14 : 1)
        .contentShape(Circle())
    }

    private func hub(scale: CGFloat) -> some View {
        let size = 104 * scale
        let selected = selection == .center
        return VStack(spacing: 4 * scale) {
            Image(systemName: centerHint.icon).font(.system(size: 20 * scale, weight: .semibold))
            Text(centerHint.label).font(.system(size: 9 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(HaloPalette.hubFill))
        .overlay(Circle().strokeBorder(selected ? AnyShapeStyle(HaloPalette.accent)
                                                 : AnyShapeStyle(HaloPalette.accent.opacity(0.5)),
                                       lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
        .scaleEffect(selected ? 1.04 : 1)
        .contentShape(Circle())
    }

    private func validGlyph(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "questionmark"
    }
}

/// Lays a `Halo` out to fit the available space — centers it and scales the whole
/// wheel down if the pane is too small, so spokes never clip. Trig lives here (not
/// in a `body`) to dodge SwiftUI's type-checker timeouts.
private struct WheelLayout {
    let center: CGPoint
    let radius: CGFloat
    let scale: CGFloat
    private let angles: [Angle]

    init(halo: Halo, size: CGSize) {
        let reach = CGFloat(halo.radius) + 46
        let fit = min(size.width, size.height) / (2 * reach)
        let s = min(1, fit)
        self.scale = s
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.radius = CGFloat(halo.radius) * s
        self.angles = halo.arc.placements(count: halo.spokes.count)
    }

    func position(_ i: Int) -> CGPoint {
        guard angles.indices.contains(i) else { return center }
        let theta = angles[i].radians
        return CGPoint(x: center.x + radius * CGFloat(cos(theta)),
                       y: center.y + radius * CGFloat(sin(theta)))
    }
}

// MARK: - Small helpers

extension Array {
    /// Bounds-checked subscript — bindings into a live config may briefly index a
    /// spoke that's been removed mid-edit.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
