import AppKit
import SwiftUI

// Shared fades keep window ownership in controllers.

extension NSWindow {
    func fadeIn(duration: TimeInterval, order: () -> Void) {
        alphaValue = 0
        order()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // AppKit runs the handler on the main thread; the parameter just isn't typed for it.
            MainActor.assumeIsolated {
                self?.invalidateShadow()
            }
        }
    }

    func fadeOut(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        }
    }

    /// Snaps back to full opacity, replacing any running fade on the same key path.
    func cancelFade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 1
        }
    }
}

extension View {
    func panelEntrance() -> some View {
        modifier(PanelEntrance())
    }
}

private struct PanelEntrance: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1 : Self.entryScale)
            .onAppear {
                withAnimation(.easeOut(duration: Theme.Duration.enter)) { appeared = true }
            }
    }

    private static let entryScale: CGFloat = 0.94
}
