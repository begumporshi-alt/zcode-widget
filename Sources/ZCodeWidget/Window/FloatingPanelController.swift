import AppKit
import SwiftUI

/// Borderless windows refuse key-window status by default, which silently
/// blocks all keyboard input (TextFields never receive focus). Overriding
/// canBecomeKey fixes that; .nonactivatingPanel lets the panel take key
/// status without activating the app, so the user's current app stays frontmost.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Panel size limits shared by the window controller and the resize grip.
enum PanelMetrics {
    static let minSize = NSSize(width: 360, height: 480)
    static let defaultSize = NSSize(width: 440, height: 560)
}

class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private static let originKey = "panelFrameOrigin"
    private static let sizeKey = "panelFrameSize"

    convenience init() {
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)
        // Belt & braces for live resize: the hosting view must track the
        // window's content bounds (a missed autoresize leaves the SwiftUI
        // surface at its old size, i.e. blank window around the content).
        hostingController.view.autoresizingMask = [.width, .height]

        // KeyablePanel (not plain NSWindow) so text fields accept typing;
        // still borderless and movable by dragging the background.
        let window = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "ZCode Widget"
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false

        // The window is closed (X) instead of terminated. App stays alive.
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.contentMinSize = PanelMetrics.minSize
        window.delegate = self
        configureWindow()
    }

    private func configureWindow() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // If the saved size is bigger than the screen (e.g. display layout
        // changed), clamp it back in. The floor is min size, unless the
        // screen itself is smaller.
        let floorW = min(PanelMetrics.minSize.width, visible.width)
        let floorH = min(PanelMetrics.minSize.height, visible.height)

        var size = PanelMetrics.defaultSize
        if let saved = UserDefaults.standard.string(forKey: Self.sizeKey) {
            let parts = saved.split(separator: ",")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                size = NSSize(width: min(max(w, floorW), visible.width),
                              height: min(max(h, floorH), visible.height))
            }
        }

        // Restore the saved position so the panel stays where the user put it,
        // clamped so the whole frame stays on-screen (a saved origin from an
        // earlier display layout can otherwise put the panel out of reach);
        // fall back to centering on first launch.
        var origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2)
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",")
            if parts.count == 2,
               let x = Double(parts[0]), let y = Double(parts[1]),
               size.width <= visible.width, size.height <= visible.height {
                origin = NSPoint(x: min(max(x, visible.minX), visible.maxX - size.width),
                                 y: min(max(y, visible.minY), visible.maxY - size.height))
            }
        }
        win.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set("\(Int(origin.x)),\(Int(origin.y))", forKey: Self.originKey)
    }

    func windowDidResize(_ notification: Notification) {
        guard let size = window?.frame.size else { return }
        UserDefaults.standard.set("\(Int(size.width)),\(Int(size.height))", forKey: Self.sizeKey)
    }
}
