import AppKit
import SwiftUI

/// Bottom-right corner grip that resizes the borderless panel. Borderless
/// windows expose no AppKit resize edges, so the grip owns the drag: it
/// tracks the mouse and grows/shrinks the window frame from its top-left
/// anchor, clamped to the visible screen and PanelMetrics.minSize.
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeGripView {
        let view = ResizeGripView()
        view.toolTip = "Drag to resize"
        return view
    }

    func updateNSView(_ nsView: ResizeGripView, context: Context) {}
}

final class ResizeGripView: NSView {
    private var dragStartFrame: NSRect = .zero
    private var dragStartLocation: NSPoint = .zero

    private static let resizeCursor: NSCursor = {
        if let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                accessibilityDescription: "Resize"),
           let image = symbol.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            return NSCursor(image: image,
                            hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
        }
        return .arrow
    }()

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Match the ticker bar's background so the grip reads as its corner.
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        guard let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                   accessibilityDescription: "Resize"),
              let config = symbol.withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) else { return }
        let tinted = config.tinted(with: .tertiaryLabelColor)
        let inset: CGFloat = 3
        let origin = NSPoint(x: bounds.width - tinted.size.width - inset,
                             y: inset)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartFrame = window.frame
        dragStartLocation = NSEvent.mouseLocation  // AppKit screen coords, bottom-left origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, dragStartFrame != .zero else { return }
        let location = NSEvent.mouseLocation
        let delta = NSSize(width: location.x - dragStartLocation.x,
                           height: location.y - dragStartLocation.y)

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? dragStartFrame
        let floorW = min(PanelMetrics.minSize.width, visible.width)
        let floorH = min(PanelMetrics.minSize.height, visible.height)
        let width = min(max(dragStartFrame.width + delta.width, floorW), visible.width)
        let height = min(max(dragStartFrame.height + delta.height, floorH), visible.height)

        window.setFrame(NSRect(origin: dragStartFrame.origin, size: NSSize(width: width, height: height)),
                        display: true)
        // Manual setFrame bypasses AppKit's live-resize session, so the
        // SwiftUI surface is not automatically re-laid out per frame — do it
        // now or the content can lag/stall behind the new window size.
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // After a drag the SwiftUI surface can be left mid-layout (blank
        // content). Force one final layout + paint pass on the next runloop
        // turn so the settled size is always fully drawn.
        guard let window else { return }
        DispatchQueue.main.async {
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
        dragStartFrame = .zero
    }
}

extension NSImage {
    /// Renders a template symbol in a color (lockFocus + sourceAtop fill).
    func tinted(with color: NSColor) -> NSImage {
        let image = copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
