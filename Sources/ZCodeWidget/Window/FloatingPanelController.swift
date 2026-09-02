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
        // Restore the saved position so the panel stays where the user put it;
        // fall back to centering on first launch.
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",")
            if parts.count == 2,
               let x = Double(parts[0]), let y = Double(parts[1]),
               let screen = NSScreen.main {
                let point = NSPoint(x: x, y: y)
                if screen.visibleFrame.insetBy(dx: -80, dy: -80).contains(point) {
                    win.setFrameOrigin(point)
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
