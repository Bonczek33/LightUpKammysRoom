import SwiftUI
import AppKit

/// Sets the containing NSWindow size exactly once.
/// Works on macOS 12+ without using Scene.defaultSize.
struct WindowDefaultSizer: ViewModifier {
    let size: CGSize
    @State private var didApply = false

    func body(content: Content) -> some View {
        content
            .background(WindowFinder { window in
                guard let window, !didApply else { return }
                didApply = true

                // Size tuned for 14" MacBook Pro: 1440 x 900 points
                var frame = window.frame
                frame.size = size

                // Keep window visible on current screen
                if let screen = window.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    frame.origin.x = visible.midX - frame.size.width / 2
                    frame.origin.y = visible.midY - frame.size.height / 2
                }

                window.setFrame(frame, display: true, animate: false)
            })
    }
}

/// Finds the nearest NSWindow hosting this SwiftUI view.
private struct WindowFinder: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            self.onResolve(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            self.onResolve(nsView?.window)
        }
    }
}

extension View {
    /// Apply a one-time default window size.
    func defaultWindowSize(_ size: CGSize) -> some View {
        self.modifier(WindowDefaultSizer(size: size))
    }
}

