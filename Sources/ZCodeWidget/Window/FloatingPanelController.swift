import AppKit
import SwiftUI

class FloatingPanelController: NSWindowController {
    convenience init() {
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)

        // Use NSWindow (not NSPanel) so the title bar / drag region works
        // and the user can grab and move the window anywhere.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.borderless, .resizable],
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
        configureWindow()
    }

    private func configureWindow() {
        guard let win = window else { return }
        // Center on screen on first launch
        win.center()
    }
}
