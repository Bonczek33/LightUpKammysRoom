//
//  WindowSizing.swift
//  LIFXBTMacApp
//
//  FIX 3 – @State in a ViewModifier is unreliable: SwiftUI can recreate the
//  modifier struct and reset instance state, causing the window to resize
//  repeatedly. Replaced with a nonisolated(unsafe) static Set so the "already
//  applied" flag survives across modifier recreations for the lifetime of the
//  process. Each unique size string is tracked independently so multiple windows
//  with different sizes still work correctly.
//

import SwiftUI
import AppKit

struct WindowDefaultSizer: ViewModifier {
    let size: CGSize

    // FIX 3: static flag — survives ViewModifier recreations.
    private nonisolated(unsafe) static var appliedSizes: Set<String> = []

    func body(content: Content) -> some View {
        content
            .background(WindowFinder { window in
                guard let window else { return }
                let key = "\(Int(size.width))x\(Int(size.height))"
                guard !Self.appliedSizes.contains(key) else { return }
                Self.appliedSizes.insert(key)

                var frame = window.frame
                frame.size = size
                if let screen = window.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    frame.origin.x = visible.midX - frame.size.width / 2
                    frame.origin.y = visible.midY - frame.size.height / 2
                }
                window.setFrame(frame, display: true, animate: false)
            })
    }
}

private struct WindowFinder: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in self.onResolve(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in self.onResolve(nsView?.window) }
    }
}

extension View {
    func defaultWindowSize(_ size: CGSize) -> some View {
        self.modifier(WindowDefaultSizer(size: size))
    }
}
