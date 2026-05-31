import AppKit
import SwiftUI

/// Presents the wheel over whatever app you're in and turns cursor motion into a
/// selection. The panel ignores mouse events — selection is read purely from the
/// cursor's angle, so the underlying app keeps focus and receives the keystroke.
///
/// Navigation into wells is *dwell-based*: hover a well to expand into it, rest
/// at the center to back out. Release is always terminal — it fires the
/// highlighted spoke, dictates (root center), or cancels (empty wedge).
final class WheelController {
    /// Supplies the halo to show (per-app profile lookup happens here).
    var haloProvider: () -> Halo = { Halo() }
    /// Released at the root center → dictate. (Voice lands later.)
    var onDictate: (() -> Void)?

    private let model = WheelModel()
    private var panel: NSPanel?
    private var tracker: Timer?

    private let canvas: CGFloat = 380
    private let deadZone: CGFloat = 34

    /// Wells we've descended into; `last` is on screen.
    private var stack: [Halo] = []
    private var current: Halo { stack.last ?? Halo() }

    private enum Dwell: Equatable { case none, well(Int), center }
    private var dwell: Dwell = .none
    private var dwellFrames = 0
    private let dwellNeeded = 18    // ~0.3s at 60 Hz

    var isShowing: Bool { panel?.isVisible ?? false }

    // MARK: - Lifecycle

    func present() {
        ensurePanel()
        stack = [haloProvider()]
        dwell = .none; dwellFrames = 0
        render()
        positionAtCursor()
        panel?.orderFrontRegardless()
        startTracking()
    }

    /// Summon button released — fire the highlighted spoke, dictate, or cancel.
    func release() {
        let wedge = model.inWedge
        let atRoot = stack.count == 1
        let spoke = model.highlighted.flatMap { current.spokes.indices.contains($0) ? current.spokes[$0] : nil }
        dismiss()
        if let spoke {
            if case .performs(let action) = spoke.content { ActionRunner.run(action) }
            // Releasing on a well does nothing — you expand it by dwelling.
        } else if !wedge && atRoot {
            onDictate?()
        }
    }

    func dismiss() {
        tracker?.invalidate(); tracker = nil
        panel?.orderOut(nil)
        stack = []
        dwell = .none; dwellFrames = 0
        model.highlighted = nil; model.inWedge = false
    }

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
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - panel.frame.midX
        let dy = mouse.y - panel.frame.midY        // screen coords: y points up

        guard hypot(dx, dy) >= deadZone else {
            model.highlighted = nil; model.inWedge = false
            advanceDwell(stack.count > 1 ? .center : .none)   // rest at center → back out
            return
        }
        // A spoke at view angle θ (y down) sits in screen space at (cos θ, −sin θ),
        // so the cursor's view angle is atan2(−dy, dx).
        let cursor = Angle.radians(atan2(-dy, dx))
        if let sel = current.arc.selection(forCursor: cursor, count: current.spokes.count) {
            model.highlighted = sel; model.inWedge = false
            advanceDwell(current.spokes[sel].isWell ? .well(sel) : .none)
        } else {
            model.highlighted = nil; model.inWedge = true
            advanceDwell(.none)
        }
    }

    /// Accumulate hover time on a navigable target; act when it crosses the dwell.
    private func advanceDwell(_ target: Dwell) {
        guard target != .none else { dwell = .none; dwellFrames = 0; return }
        if dwell == target { dwellFrames += 1 } else { dwell = target; dwellFrames = 1 }
        guard dwellFrames >= dwellNeeded else { return }
        dwell = .none; dwellFrames = 0
        switch target {
        case .well(let i): expand(i)
        case .center:      pop()
        case .none:        break
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
