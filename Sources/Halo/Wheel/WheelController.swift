import AppKit
import SwiftUI

/// Presents the wheel over whatever app you're in and turns cursor motion into a
/// selection. The panel ignores mouse events — selection is read purely from the
/// cursor's angle, so the underlying app keeps focus and receives the keystroke.
///
/// Navigation into wells is dwell-based; release is terminal. Dictation depends
/// on `voiceMode`:
///   • handsFree  — release at center starts a session (the app shows a pill and
///                  stops on the next summon press).
///   • pushToTalk — dwell at center starts recording (hub shows it); release sends.
final class WheelController {
    var haloProvider: () -> Halo = { Halo() }

    // Voice hooks, interpreted by the app per the active mode.
    var voiceMode: () -> VoiceMode = { .handsFree }
    var canRecord: () -> Bool = { false }
    var onCenterHold: () -> Void = {}      // push-to-talk: start recording
    var onCenterRelease: () -> Void = {}   // push-to-talk: send · hands-free: start session
    var levelProvider: () -> Float = { 0 } // current mic level for the waveform

    private var levelTimer: Timer?

    private let model = WheelModel()
    private var panel: NSPanel?
    private var tracker: Timer?

    private let canvas: CGFloat = 380
    private let deadZone: CGFloat = 34

    private var stack: [Halo] = []
    private var current: Halo { stack.last ?? Halo() }

    private enum Dwell: Equatable { case none, well(Int), center, recordCenter }
    private var dwell: Dwell = .none
    private var dwellFrames = 0
    private let dwellNeeded = 18    // ~0.3s at 60 Hz

    private var hideToken = 0

    var isShowing: Bool { panel?.isVisible ?? false }

    // MARK: - Lifecycle

    func present() {
        ensurePanel()
        hideToken += 1
        stack = [haloProvider()]
        dwell = .none; dwellFrames = 0
        render()
        positionAtCursor()
        panel?.orderFrontRegardless()
        startTracking()
    }

    func release() {
        if model.recording {                  // push-to-talk: release sends (hub stays for transcribing)
            onCenterRelease()
            return
        }
        let wedge = model.inWedge
        let atRoot = stack.count == 1
        let spoke = model.highlighted.flatMap { current.spokes.indices.contains($0) ? current.spokes[$0] : nil }
        if spoke == nil, !wedge, atRoot, canRecord(), voiceMode() == .handsFree {
            onCenterRelease()                  // hands-free: start a session (hub stays up)
            return
        }
        dismiss()
        if let spoke, case .performs(let action) = spoke.content { ActionRunner.run(action) }
    }

    func dismiss() {
        tracker?.invalidate(); tracker = nil
        stopLevelTimer()
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
        model.transcribing = false
        model.recording = true
        model.levels = []
        startLevelTimer()
    }

    /// Recording stopped — show transcribing in the hub until it completes.
    func markTranscribing() {
        stopLevelTimer()
        model.recording = false
        model.transcribing = true
    }

    /// Session finished — collapse the hub away.
    func endVoiceSession() {
        model.transcribing = false
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

    // MARK: - Levels

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
        model.modelLoading = false
        model.levels = []
        model.revealID += 1
    }

    private func expand(_ index: Int) {
        guard current.spokes.indices.contains(index),
              case .opens(let child) = current.spokes[index].content else { return }
        stack.append(child)
        render()
    }

    private func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
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
        if model.recording { return }          // push-to-talk hold: ignore movement
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - panel.frame.midX
        let dy = mouse.y - panel.frame.midY

        guard hypot(dx, dy) >= deadZone else {  // center deadzone
            model.highlighted = nil; model.inWedge = false
            if stack.count > 1 {
                model.modelLoading = false
                advanceDwell(.center)                          // sub-ring: rest to back out
            } else if !canRecord() {
                model.modelLoading = true                      // model still loading
                advanceDwell(.none)
            } else {
                model.modelLoading = false
                advanceDwell(voiceMode() == .pushToTalk ? .recordCenter : .none)
            }
            return
        }
        model.modelLoading = false
        let cursor = Angle.radians(atan2(-dy, dx))
        if let sel = current.arc.selection(forCursor: cursor, count: current.spokes.count) {
            model.highlighted = sel; model.inWedge = false
            advanceDwell(current.spokes[sel].isWell ? .well(sel) : .none)
        } else {
            model.highlighted = nil; model.inWedge = true
            advanceDwell(.none)
        }
    }

    private func advanceDwell(_ target: Dwell) {
        guard target != .none else { dwell = .none; dwellFrames = 0; return }
        if dwell == target { dwellFrames += 1 } else { dwell = target; dwellFrames = 1 }
        guard dwellFrames >= dwellNeeded else { return }
        dwell = .none; dwellFrames = 0
        switch target {
        case .well(let i):   expand(i)
        case .center:        pop()
        case .recordCenter:  model.recording = true; model.levels = []; onCenterHold(); startLevelTimer()
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
