import AppKit
import SwiftUI

/// A faint backdrop blur + desaturation behind a floating bar, layered under the list's
/// `edgeDissolve` mask — macOS variable blur (`CABackdropLayer` + `CAFilter("variableBlur")`, the
/// windowserver machinery behind `NSVisualEffectView`). Deliberately subtle: the dissolve carries
/// the edge; this takes the crispness off and mattes the melt zone toward a Raycast-like gray.
/// Sized taller than the dissolve band (via `reach`) so rows just past the fade keep a whisper of
/// softness instead of snapping sharp at the band's end.
struct EdgeBlur: View {
    /// Blur strength from the panel edge (location 0) to the content side (location 1), as fractions of `radius`.
    typealias Falloff = [(location: CGFloat, alpha: CGFloat)]

    let edge: VerticalEdge
    /// Blur radius at the panel edge, eased down to 0 at the content side. Kept small — the
    /// dissolve does the hiding; anything stronger reads as a frosted strip.
    var radius: CGFloat = 1.5
    /// Extra distance the blur reaches past the bar into the list (negative shrinks); never affects the bar's layout.
    var reach: CGFloat = 0
    /// Defaults hold strength tight against the edge, then trail off long and low.
    var falloff: Falloff = [(0.0, 1.0), (0.2, 0.8), (0.5, 0.45), (0.75, 0.18), (1.0, 0.0)]
    /// Backdrop saturation: 1 is neutral, below 1 mattes the blur's sheen; masked by `falloff`, so it fades like the blur instead of boxing.
    var saturation: CGFloat = 0.2

    var body: some View {
        VariableBlurBackdrop(edge: edge, radius: radius, falloff: falloff, saturation: saturation)
            .padding(edge == .top ? .bottom : .top, -reach)
            .allowsHitTesting(false)
    }
}

private struct VariableBlurBackdrop: NSViewRepresentable {
    let edge: VerticalEdge
    let radius: CGFloat
    let falloff: EdgeBlur.Falloff
    let saturation: CGFloat

    func makeNSView(context: Context) -> VariableBlurView {
        VariableBlurView(edge: edge, radius: radius, falloff: falloff, saturation: saturation)
    }

    func updateNSView(_ nsView: VariableBlurView, context: Context) {}
}

final class VariableBlurView: NSView {
    init(edge: VerticalEdge, radius: CGFloat, falloff: EdgeBlur.Falloff, saturation: CGFloat) {
        super.init(frame: .zero)
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
            let maskImage = Self.gradientMask(edge: edge, falloff: falloff),
            let blur = Self.variableBlurFilter(radius: radius, mask: maskImage)
        else {
            // No fallback: the dissolve alone already reads clean, so a missing private class
            // just means no extra softness rather than a mismatched material scrim.
            wantsLayer = true
            return
        }
        let root = CALayer()
        let blurLayer = backdropClass.init()
        blurLayer.filters = [blur]
        // The backdrop layers span the panel's full width, so their outer corners overlap the
        // panel's rounded corner arcs — unclipped, they sample the bright desktop behind the
        // window there and paint it as white corner spots. Backdrop layers ignore ancestor
        // masksToBounds, so the panel-radius clip must sit on each backdrop layer itself; the
        // inner corners lose only near-zero-strength blur, which is invisible.
        Self.clipToPanelCorners(blurLayer)
        root.addSublayer(blurLayer)
        // Saturation rides a second backdrop over the blurred result, gradient-masked so it melts with the blur.
        if saturation != 1, let saturate = Self.saturationFilter(amount: saturation) {
            let satLayer = backdropClass.init()
            satLayer.filters = [saturate]
            Self.clipToPanelCorners(satLayer)
            let mask = CALayer()
            mask.contents = maskImage
            mask.contentsGravity = .resize
            satLayer.mask = mask
            root.addSublayer(satLayer)
        }
        // Layer-hosting (layer assigned before wantsLayer): AppKit silently clears filters on layer-backed views.
        layer = root
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Decorative only — never intercept clicks meant for the bar's controls.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        syncSublayerFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSublayerFrames()
    }

    /// Hosted sublayers don't track the view's size on their own.
    private func syncSublayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in layer?.sublayers ?? [] {
            sublayer.frame = bounds
            sublayer.mask?.frame = CGRect(origin: .zero, size: bounds.size)
        }
        CATransaction.commit()
    }

    private static func clipToPanelCorners(_ layer: CALayer) {
        layer.cornerRadius = Theme.Radius.panel
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    /// `CAFilter("variableBlur")` scaling `radius` per-pixel by the mask's alpha.
    private static func variableBlurFilter(radius: CGFloat, mask: CGImage) -> NSObject? {
        guard let filter = caFilter(type: "variableBlur") else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// `CAFilter("colorSaturate")` — the system materials' vibrancy filter, dialed below 1 for matte.
    private static func saturationFilter(amount: CGFloat) -> NSObject? {
        guard let filter = caFilter(type: "colorSaturate") else { return nil }
        filter.setValue(amount, forKey: "inputAmount")
        return filter
    }

    private static func caFilter(type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
            let filter = filterClass.perform(selector, with: type)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        return filter
    }

    /// The falloff rendered as a vertical alpha gradient, opaque at the panel edge.
    private static func gradientMask(
        edge: VerticalEdge, falloff stops: EdgeBlur.Falloff
    ) -> CGImage? {
        let height = 96
        guard
            let context = CGContext(
                data: nil, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { CGColor(gray: 0, alpha: $0.alpha) } as CFArray,
                locations: stops.map(\.location)
            )
        else { return nil }
        // CG origin is bottom-left; a CGImage renders with its top row at the layer's top.
        let edgeY: CGFloat = edge == .top ? CGFloat(height) : 0
        let innerY: CGFloat = edge == .top ? 0 : CGFloat(height)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: edgeY), end: CGPoint(x: 0, y: innerY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return context.makeImage()
    }
}
