import AppKit
import SwiftUI

/// True variable-radius "melting" backdrop blur behind a floating bar — the macOS equivalent of
/// iOS's `UIBlurEffect.effectWithVariableBlurRadius:imageMask:` (the status-bar melt).
///
/// The view's backing layer is a `CABackdropLayer` carrying a `CAFilter` of type `variableBlur`:
/// the windowserver blurs whatever is composited behind the layer in this window, scaling the
/// radius per-pixel by the alpha of a gradient mask (full radius at the panel edge → 0 at the
/// content side). Being windowserver-composited is the point — Core Image `backgroundFilters`
/// never render in this transparent panel, and `NSVisualEffectView` can't vary its radius.
/// Both classes are private but stable (they're what `NSVisualEffectView` and the system scroll
/// edge effect are built on); if either ever disappears, we fall back to a gradient-masked
/// `NSVisualEffectView` so the bars never lose separation entirely.
struct ProgressiveEdgeBlur: View {
    /// Alpha ramp from the panel edge (location 0) to the content side (location 1); each alpha
    /// is the fraction of `radius` applied at that depth.
    typealias Falloff = [(location: CGFloat, alpha: CGFloat)]

    let edge: VerticalEdge
    /// Blur radius at the panel edge; the falloff eases it down to 0 at the content side.
    var radius: CGFloat = 2
    /// Extra distance the melt reaches past the bar into the list. Applied as negative padding on
    /// the bar's background, so it never affects the bar's own layout (negative values shrink the
    /// blur region to less than the bar).
    var reach: CGFloat = 12
    /// Defaults hold strength tight against the edge, then let go.
    var falloff: Falloff = [(0.0, 1.0), (0.2, 0.8), (0.5, 0.45), (0.75, 0.18), (1.0, 0.0)]
    /// Backdrop saturation under the blur: 1 is neutral, below 1 mattes down the glossy sheen the
    /// blur makes by smearing bright pixels. Beware: unlike the blur it is NOT masked by `falloff`
    /// — it covers the whole bar rect, and over bright desktops behind the translucent panel it
    /// reads as a hard-edged gray region, so keep it at (or very near) 1.
    var saturation: CGFloat = 1

    var body: some View {
        VariableBlurBackdrop(edge: edge, radius: radius, falloff: falloff, saturation: saturation)
            .padding(edge == .top ? .bottom : .top, -reach)
            .allowsHitTesting(false)
    }
}

private struct VariableBlurBackdrop: NSViewRepresentable {
    let edge: VerticalEdge
    let radius: CGFloat
    let falloff: ProgressiveEdgeBlur.Falloff
    let saturation: CGFloat

    func makeNSView(context: Context) -> ProgressiveBlurView {
        ProgressiveBlurView(edge: edge, radius: radius, falloff: falloff, saturation: saturation)
    }

    func updateNSView(_ nsView: ProgressiveBlurView, context: Context) {}
}

final class ProgressiveBlurView: NSView {
    private let edge: VerticalEdge

    init(
        edge: VerticalEdge, radius: CGFloat, falloff: ProgressiveEdgeBlur.Falloff,
        saturation: CGFloat = 1
    ) {
        self.edge = edge
        super.init(frame: .zero)
        if let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
            let mask = Self.gradientMask(edge: edge, falloff: falloff),
            let blur = Self.variableBlurFilter(radius: radius, mask: mask)
        {
            // Layer-hosting, not layer-backed: assigning `layer` before `wantsLayer` hands us
            // ownership of the layer's properties. A layer-backed view won't do — AppKit manages
            // its backing layer and silently clears `filters` during setup.
            let backdrop = backdropClass.init()
            var filters: [Any] = [blur]
            if saturation != 1, let saturate = Self.saturationFilter(amount: saturation) {
                filters.insert(saturate, at: 0)
            }
            backdrop.filters = filters
            layer = backdrop
            wantsLayer = true
        } else {
            wantsLayer = true
            installFallback()
        }
    }

    /// `CAFilter.filterWithType("colorSaturate")` — same backdrop filter the system materials use
    /// for vibrancy, here dialed below 1 to matte the blur down instead of juicing it up.
    private static func saturationFilter(amount: CGFloat) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
            let filter = filterClass.perform(selector, with: "colorSaturate")?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(amount, forKey: "inputAmount")
        return filter
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Purely decorative backdrop — never intercept clicks meant for the bar's controls.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `CAFilter.filterWithType("variableBlur")` configured like the iOS variable blur effect.
    private static func variableBlurFilter(radius: CGFloat, mask: CGImage) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
            let filter = filterClass.perform(selector, with: "variableBlur")?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// Vertical alpha ramp stretched over the layer: opaque (full radius) at the panel edge,
    /// eased down to clear at the content side so the blur melts instead of cutting off.
    private static func gradientMask(
        edge: VerticalEdge, falloff stops: ProgressiveEdgeBlur.Falloff
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

    /// If the private backdrop machinery ever goes away: a gradient-masked material blur, so the
    /// bars still separate from the list (fixed radius, but never a hard edge).
    private func installFallback() {
        let effect = NSVisualEffectView()
        effect.blendingMode = .withinWindow
        effect.material = .hudWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.frame = bounds
        let isTop = edge == .top
        effect.maskImage = NSImage(
            size: NSSize(width: 1, height: 96), flipped: false
        ) { rect in
            guard let context = NSGraphicsContext.current?.cgContext,
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray,
                    locations: [0, 1]
                )
            else { return false }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: isTop ? rect.maxY : 0),
                end: CGPoint(x: 0, y: isTop ? 0 : rect.maxY),
                options: []
            )
            return true
        }
        effect.maskImage?.resizingMode = .stretch
        addSubview(effect)
    }
}
