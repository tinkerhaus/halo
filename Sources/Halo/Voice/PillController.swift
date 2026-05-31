import AppKit
import SwiftUI

/// Hosts the floating dictation pill in a borderless, non-activating panel near
/// the cursor. Purely informational — it ignores mouse events.
final class PillController {
    private var panel: NSPanel?

    func show(voice: Voice, near point: NSPoint) {
        let size = NSSize(width: 280, height: 60)
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.hasShadow = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            self.panel = panel
        }
        guard let panel else { return }
        let host = NSHostingView(rootView: ZStack { PillView(voice: voice) }
            .frame(width: size.width, height: size.height))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        // Sit just below the release point, clamped on screen.
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            origin.y = max(origin.y, vf.minY + 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}
