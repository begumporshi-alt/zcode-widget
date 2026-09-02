import AppKit
import SwiftUI

/// Borderless windows refuse key-window status by default, which silently
/// blocks all keyboard input (TextFields never receive focus). Overriding
/// canBecomeKey fixes that; .nonactivatingPanel lets the panel take key
/// status without activating the app, so the user's current app stays frontmost.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private static let originKey = "panelFrameOrigin"

    convenience init() {
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)

        // KeyablePanel (not plain NSWindow) so text fields accept typing;
        // still borderless and movable by dragging the background.
        let window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
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
        window.delegate = self
        configureWindow()
    }

    private func configureWindow() {
        guard let win = window else { return }
        // Restore the saved position so the panel stays where the user put it,
        // clamped so the whole frame stays on-screen (a saved origin from an
        // earlier display layout can otherwise put the panel out of reach);
        // fall back to centering on first launch.
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",")
            if parts.count == 2,
               let x = Double(parts[0]), let y = Double(parts[1]),
               let screen = NSScreen.main {
                let size = win.frame.size
                let visible = screen.visibleFrame
                if size.width <= visible.width, size.height <= visible.height {
                    let clampedX = min(max(x, visible.minX), visible.maxX - size.width)
                    let clampedY = min(max(y, visible.minY), visible.maxY - size.height)
                    win.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
                    return
                }
            }
        }
        win.center()
    }

    func windowDidMove(_ notification: Notification) {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set("\(Int(origin.x)),\(Int(origin.y))", forKey: Self.originKey)
    }
}
