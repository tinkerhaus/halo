import SwiftUI
import AppKit

/// A circular **behind-window** vibrancy view — frosts the real content *behind the
/// window* (the app the wheel floats over). The native in-window `glassEffect` can't
/// do that for a transparent overlay, so this is the right tool for the wheel. Works
/// on every supported macOS version.
struct FrostCircle: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = CircularVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Masks the vibrancy to a circle (NSVisualEffectView honours `maskImage`).
final class CircularVisualEffectView: NSVisualEffectView {
    override func layout() {
        super.layout()
        maskImage = Self.circleMask(diameter: bounds.width)
    }
    private static func circleMask(diameter: CGFloat) -> NSImage? {
        guard diameter > 0 else { return nil }
        return NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

/// A rounded-rect behind-window vibrancy view — for floating overlay panels like
/// the dictation transcript caption.
struct FrostRoundedRect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = RoundedVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.cornerRadius = cornerRadius
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        (view as? RoundedVisualEffectView)?.cornerRadius = cornerRadius
    }
}

final class RoundedVisualEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 14 { didSet { needsLayout = true } }
    override func layout() {
        super.layout()
        maskImage = Self.mask(size: bounds.size, radius: cornerRadius)
    }
    private static func mask(size: NSSize, radius: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let r = min(radius, min(size.width, size.height) / 2)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
    }
}

/// Liquid Glass helpers, availability-gated.
///
/// On **macOS 26+** these use the native `glassEffect` system, which renders real
/// lensing, specular highlights, and adaptive shadows — so we must **not** add our
/// own borders/bevels/blur (that's the Utter mistake). On older systems they fall
/// back to the prior solid styling. Glass belongs on the *control* layer only
/// (the hub, spokes, toolbars) — never on content.

/// A circular glass surface. A non-nil `tint` (e.g. the accent) marks a *selected*
/// element — tinting should be semantic, not everywhere.
struct GlassDisc: ViewModifier {
    var tint: Color? = nil
    var fallbackFill: AnyShapeStyle
    var ringOpacity: Double = 0
    var shadowRadius: CGFloat = 7
    var shadowOpacity: Double = 0.45

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: Circle())
        } else {
            content
                .background(Circle().fill(fallbackFill))
                .overlay(Circle().strokeBorder(.white.opacity(ringOpacity), lineWidth: 1).padding(-3.5))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: 3)
        }
    }

    @available(macOS 26, *)
    private var glass: Glass { tint.map { Glass.regular.tint($0) } ?? .regular }
}

/// A rounded-rectangle glass surface — for panels/cards/toolbars.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 12
    var tint: Color? = nil
    var fallback: AnyShapeStyle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fallback))
        }
    }

    @available(macOS 26, *)
    private var glass: Glass { tint.map { Glass.regular.tint($0) } ?? .regular }
}

/// Morph identity: an element liquid-morphs as it appears / moves within a
/// `GlassEffectContainer` (no-op below macOS 26).
struct GlassMorphID: ViewModifier {
    let id: AnyHashable
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.glassEffectID(id, in: namespace) }
        else { content }
    }
}

/// Group glass shapes so they share one sampling region and morph together as they
/// move within `spacing` of each other (no-op below macOS 26).
struct GlassGroup: ViewModifier {
    var spacing: CGFloat = 20
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content } }
        else { content }
    }
}

extension View {
    func glassDisc(tint: Color? = nil, fallbackFill: AnyShapeStyle, ringOpacity: Double = 0,
                   shadowRadius: CGFloat = 7, shadowOpacity: Double = 0.45) -> some View {
        modifier(GlassDisc(tint: tint, fallbackFill: fallbackFill, ringOpacity: ringOpacity,
                           shadowRadius: shadowRadius, shadowOpacity: shadowOpacity))
    }
    func glassPanel(cornerRadius: CGFloat = 12, tint: Color? = nil, fallback: AnyShapeStyle) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, fallback: fallback))
    }
    func glassMorphID(_ id: AnyHashable, in namespace: Namespace.ID) -> some View {
        modifier(GlassMorphID(id: id, namespace: namespace))
    }
    func glassGroup(spacing: CGFloat = 20) -> some View {
        modifier(GlassGroup(spacing: spacing))
    }
}
