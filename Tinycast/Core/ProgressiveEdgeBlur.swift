import AppKit
import SwiftUI

/// Progressive "melting" edge blur behind a floating bar — macOS variable blur (`CABackdropLayer` + `CAFilter("variableBlur")`, the windowserver machinery behind `NSVisualEffectView` and iOS's status-bar melt).
struct ProgressiveEdgeBlur: View {
    /// Alpha ramp from the panel edge (location 0) to the content side (location 1), as fractions of `radius`.
    typealias Falloff = [(location: CGFloat, alpha: CGFloat)]

    let edge: VerticalEdge
    /// Blur radius at the panel edge, eased down to 0 at the content side.
    var radius: CGFloat = 3
    /// Extra distance the melt reaches past the bar into the list (negative shrinks); never affects the bar's layout.
    var reach: CGFloat = 8
    /// Defaults hold strength tight against the edge, then let go.
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
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
            let maskImage = Self.gradientMask(edge: edge, falloff: falloff),
            let blur = Self.variableBlurFilter(radius: radius, mask: maskImage)
        else {
            wantsLayer = true
            installFallback()
            return
        }
        let root = CALayer()
        let blurLayer = backdropClass.init()
        blurLayer.filters = [blur]
        root.addSublayer(blurLayer)
        // Saturation rides a second backdrop over the blurred result, gradient-masked so it melts with the blur.
        if saturation != 1, let saturate = Self.saturationFilter(amount: saturation) {
            let satLayer = backdropClass.init()
            satLayer.filters = [saturate]
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

    /// Gradient-masked material blur in case the private backdrop classes ever disappear.
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
