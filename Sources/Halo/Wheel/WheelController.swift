import AppKit
import SwiftUI

/// Presents the wheel over whatever app you're in and turns cursor motion into a
/// selection. The panel ignores mouse events — selection is read purely from the
/// cursor's angle, so the underlying app keeps focus and receives the keystroke.
///
/// Navigation into wells is dwell-based; release is terminal. What release does:
///   • on a spoke   → fire its action
///   • in the wedge → cancel (discard a dictation if one is active, else dismiss)
///   • at center    → dictate (at *any* depth); a finish ring's center sends instead
///
/// A well opens onto the *parent's* ring with a **Back** spoke sitting where the
/// well was — so the same place takes you in and back out (dwell Back to return).
///
/// Dictation: release-at-center starts a hands-free session (the hub becomes the
/// live recording UI). Pressing summon again presents the *finish* halo — release
/// to Send / Send+Return / Cancel. The session's verbs (`dictate`/`send`/`cancel`)
/// run through `ActionRunner` and manage the hub themselves, so the controller
/// only dismisses for plain keystroke actions.
final class WheelController {
    var haloProvider: () -> Halo = { Halo() }
    var canRecord: () -> Bool = { false }      // dictation model is ready
    var hasSession: () -> Bool = { false }     // a hands-free session is active
    var levelProvider: () -> Float = { 0 }     // current mic level for the waveform

    private var levelTimer: Timer?

    private let model = WheelModel()
    private var panel: NSPanel?
    private var captionPanel: NSPanel?      // the transcript bubble, floating above the wheel
    private var tracker: Timer?

    private let canvas: CGFloat = 380
    private let deadZone: CGFloat = 34

    /// A displayed ring plus which of its spokes is the Back button (nil at the root).
    private struct Level { let halo: Halo; let backIndex: Int? }
    private var stack: [Level] = []
    private var current: Halo { stack.last?.halo ?? Halo() }
    private var currentBackIndex: Int? { stack.last?.backIndex }

    private enum Dwell: Equatable { case none, well(Int), back }
    private var dwell: Dwell = .none
    private var dwellFrames = 0
    private let dwellNeeded = 18    // ~0.3s at 60 Hz
    private var backArmed = false   // suppress an instant bounce-back right after a well opens

    private var hideToken = 0
    private var lastHighlight: Int?      // for the soft select tick

    var isShowing: Bool { panel?.isVisible ?? false }

    // MARK: - Lifecycle

    /// Show the wheel for the current halo (action wheel, or the finish ring when
    /// a session is active — the provider decides).
    func present() {
        ensurePanel()
        hideToken += 1
        stack = [Level(halo: haloProvider(), backIndex: nil)]
        dwell = .none; dwellFrames = 0
        backArmed = true
        lastHighlight = nil
        render()
        positionAtCursor()
        panel?.orderFrontRegardless()
        startTracking()
        Sounds.shared.play(.summon)
    }

    func release() {
        if let h = model.highlighted {
            if h == currentBackIndex { dismiss(); return }       // released on Back → just close
            let spoke = current.spokes.indices.contains(h) ? current.spokes[h] : nil
            if case .performs(let action)? = spoke?.content { fire(action) } else { dismiss() }
            return
        }
        if model.inWedge {
            if hasSession() { fire(Action([.verb(.cancel)])) } else { Sounds.shared.play(.cancel); dismiss() }
            return
        }
        // Center — always dictates at any depth; a finish ring keeps its configured center (send).
        if let action = current.center {
            fire(action)
        } else if canRecord() {
            fire(Action([.verb(.dictate)]))
        } else {
            dismiss()
        }
    }

    /// Run an action. Session verbs (dictate/send/cancel) drive the hub and its
    /// eventual dismissal themselves; everything else dismisses the wheel first.
    private func fire(_ action: Action) {
        if managesSession(action) {
            ActionRunner.run(action)
        } else {
            Sounds.shared.play(.fire)
            dismiss()
            ActionRunner.run(action)
        }
    }

    private func managesSession(_ action: Action) -> Bool {
        action.steps.contains {
            if case .verb(let v) = $0 { return v != .undo }
            return false
        }
    }

    func dismiss() {
        tracker?.invalidate(); tracker = nil
        stopLevelTimer()
        hideCaption()
        dwell = .none; dwellFrames = 0
        model.recording = false; model.transcribing = false; model.modelLoading = false
        model.collapseID += 1
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.panel?.orderOut(nil)
            self.stack = []
            self.model.highlighted = nil; self.model.inWedge = false
            self.model.levels = []
        }
    }

    // MARK: - Voice session (the hub *is* the recording UI — no separate pill)

    /// Hands-free: keep the hub on screen as the live recording UI.
    func beginVoiceSession() {
        hideToken += 1                          // cancel any pending hide
        tracker?.invalidate(); tracker = nil
        model.highlighted = nil; model.inWedge = false; model.modelLoading = false
        model.transcribing = false; model.finishing = false; model.transcript = ""
        model.recording = true
        model.levels = []
        hideCaption()
        startLevelTimer()
    }

    /// Finish ring is up; transcription is running — surface it in the caption above the wheel.
    func markTranscribing() {
        stopLevelTimer()
        model.recording = false
        model.transcribing = true
        showCaption()
    }

    /// The transcript is ready — preview it in the hub (release at center to send).
    func showTranscript(_ text: String) {
        model.transcribing = false
        model.transcript = text
    }

    /// Session finished — collapse the hub away.
    func endVoiceSession() {
        model.transcribing = false; model.transcript = ""; model.finishing = false
        dismiss()
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.levels.append(self.levelProvider())
            if self.model.levels.count > 48 { self.model.levels.removeFirst(self.model.levels.count - 48) }
        }
    }

    private func stopLevelTimer() { levelTimer?.invalidate(); levelTimer = nil }

    // MARK: - Rendering

    private func render() {
        model.spokes = current.spokes.enumerated().map { i, s in
            WheelSpoke(id: i, label: s.label, glyph: s.glyph, isWell: s.isWell)
        }
        model.angles = current.arc.placements(count: current.spokes.count)
        model.radius = CGFloat(current.radius)
        model.depth = stack.count - 1
        model.highlighted = nil
        model.inWedge = false
        model.recording = false
        model.transcribing = false
        model.finishing = hasSession()      // presenting during a session ⇒ this is the finish ring
        model.transcript = ""
        model.modelLoading = false
        model.levels = []
        hideCaption()
        model.revealID += 1
    }

    private func expand(_ index: Int) {
        guard current.spokes.indices.contains(index),
              case .opens(let child) = current.spokes[index].content else { return }
        let built = Halo.subRing(opening: child, on: current, wellIndex: index)
        backArmed = false                       // require leaving Back once before it can fire
        stack.append(Level(halo: built.halo, backIndex: built.backIndex))
        render()
    }

    private func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        backArmed = true
        render()
    }

    // MARK: - Tracking

    private func startTracking() {
        tracker?.invalidate()
        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.track()
        }
    }

    private func track() {
        guard let panel else { return }
        defer { announceSelection() }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - panel.frame.midX
        let dy = mouse.y - panel.frame.midY

        guard hypot(dx, dy) >= deadZone else {  // center deadzone — always dictates on release
            model.highlighted = nil; model.inWedge = false
            backArmed = true                               // cursor is off the Back spoke
            model.modelLoading = current.center == nil && !canRecord()
            advanceDwell(.none)
            return
        }
        model.modelLoading = false
        let cursor = Angle.radians(atan2(-dy, dx))
        if let sel = current.arc.selection(forCursor: cursor, count: current.spokes.count) {
            model.highlighted = sel; model.inWedge = false
            if sel == currentBackIndex {
                advanceDwell(backArmed ? .back : .none)    // dwell to go back, once armed
            } else {
                backArmed = true
                advanceDwell(current.spokes[sel].isWell ? .well(sel) : .none)
            }
        } else {
            model.highlighted = nil; model.inWedge = true
            backArmed = true
            advanceDwell(.none)
        }
    }

    /// A whisper-soft tick when the highlighted spoke changes (not while recording).
    private func announceSelection() {
        guard model.highlighted != lastHighlight else { return }
        if model.highlighted != nil, !model.recording { Sounds.shared.play(.select) }
        lastHighlight = model.highlighted
    }

    private func advanceDwell(_ target: Dwell) {
        guard target != .none else { dwell = .none; dwellFrames = 0; return }
        if dwell == target { dwellFrames += 1 } else { dwell = target; dwellFrames = 1 }
        guard dwellFrames >= dwellNeeded else { return }
        dwell = .none; dwellFrames = 0
        switch target {
        case .well(let i):   expand(i)
        case .back:          pop()
        case .none:          break
        }
    }

    // MARK: - Panel

    private func positionAtCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        var center = mouse
        let reach = CGFloat(current.radius) + 40
        let margin: CGFloat = 12
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if vf.minX + reach + margin <= vf.maxX - reach - margin {
                center.x = min(max(center.x, vf.minX + reach + margin), vf.maxX - reach - margin)
            }
            if vf.minY + reach + margin <= vf.maxY - reach - margin {
                center.y = min(max(center.y, vf.minY + reach + margin), vf.maxY - reach - margin)
            }
        }
        panel.setFrameOrigin(NSPoint(x: center.x - canvas / 2, y: center.y - canvas / 2))
    }

    // MARK: - Transcript caption (a second panel floating above the wheel)

    private func showCaption() {
        ensureCaptionPanel()
        positionCaption()
        captionPanel?.orderFrontRegardless()
    }

    private func hideCaption() { captionPanel?.orderOut(nil) }

    /// Sit the caption's bottom just above whatever the wheel reaches highest —
    /// the topmost spoke, or the hub when the top is empty. Computed from the live
    /// halo so a finish ring with a spoke up top no longer collides with the bubble.
    private func positionCaption() {
        guard let wheel = panel, let cap = captionPanel else { return }
        let r = CGFloat(current.radius)
        let spokeHalf: CGFloat = 34            // half a spoke chip, plus a hair
        let hubTop: CGFloat = 56               // floor: just above the hub
        let margin: CGFloat = 12
        // How far above center each spoke reaches (screen y is up; the upward
        // component for a spoke at view-angle θ is −r·sin θ). Empty → hub top.
        let topReach = current.arc.placements(count: current.spokes.count)
            .map { -r * CGFloat(sin($0.radians)) }
            .max()
            .map { max($0 + spokeHalf, hubTop) } ?? hubTop
        let x = wheel.frame.midX - cap.frame.width / 2
        let y = wheel.frame.midY + topReach + margin
        cap.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func ensureCaptionPanel() {
        guard captionPanel == nil else { return }
        let hosting = NSHostingView(rootView: TranscriptCaption(model: model))
        hosting.setFrameSize(NSSize(width: 380, height: 220))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.layer?.masksToBounds = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.hasShadow = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.becomesKeyOnlyIfNeeded = true
        p.contentView = hosting
        captionPanel = p
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: WheelView(model: model))
        hosting.setFrameSize(NSSize(width: canvas, height: canvas))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.layer?.masksToBounds = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        self.panel = panel
    }
}
