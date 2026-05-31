import AppKit
import SwiftUI

/// Presents the wheel over whatever app you're in and turns cursor motion into a
/// selection. The panel ignores mouse events — selection is read purely from the
/// cursor's angle, so the underlying app keeps focus and receives the keystroke.
final class WheelController {
    /// Supplies the halo to show (per-app profile lookup happens here).
    var haloProvider: () -> Halo = { Halo() }
    /// Released at the center → dictate. (Voice lands later.)
    var onDictate: (() -> Void)?

    private let model = WheelModel()
    private var panel: NSPanel?
    private var tracker: Timer?

    private let canvas: CGFloat = 380
    private let deadZone: CGFloat = 34
    private var halo = Halo()

    var isShowing: Bool { panel?.isVisible ?? false }

    func present() {
        ensurePanel()
        halo = haloProvider()
        model.spokes = halo.spokes.enumerated().map { i, s in
            WheelSpoke(id: i, label: s.label, glyph: s.glyph, isWell: s.isWell)
        }
        model.angles = halo.arc.placements(count: halo.spokes.count)
        model.radius = CGFloat(halo.radius)
        model.highlighted = nil
        model.inWedge = false
        positionAtCursor()
        panel?.orderFrontRegardless()
        startTracking()
    }

    /// Called when the summon button is released — fire the selection, or dictate
    /// / cancel.
    func release() {
        let selection = model.highlighted
        let wedge = model.inWedge
        dismiss()

        if let i = selection, halo.spokes.indices.contains(i) {
            switch halo.spokes[i].content {
            case .performs(let action): ActionRunner.run(action)
            case .opens:                break   // wells expand on dwell (lands later)
            }
        } else if !wedge {
            onDictate?()                          // released at center
        }
    }

    func dismiss() {
        tracker?.invalidate(); tracker = nil
        panel?.orderOut(nil)
        model.highlighted = nil
        model.inWedge = false
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
            model.highlighted = nil; model.inWedge = false; return   // center → dictate
        }
        // A spoke at view angle θ (y down) sits in screen space at (cos θ, −sin θ),
        // so the cursor's view angle is atan2(−dy, dx).
        let cursor = Angle.radians(atan2(-dy, dx))
        if let sel = halo.arc.selection(forCursor: cursor, count: halo.spokes.count) {
            model.highlighted = sel; model.inWedge = false
        } else {
            model.highlighted = nil; model.inWedge = true
        }
    }

    // MARK: - Panel

    private func positionAtCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        var center = mouse
        let reach = CGFloat(halo.radius) + 40
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
