import AppKit

@main
struct ZCodeWidgetApp {
    static func main() {
        let app = NSApplication.shared
        // Use .regular so we can have a status bar item and stay alive
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var statusView: StatusItemView?
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Hidden main menu — an accessory app has no menu bar, so without an
        // Edit menu AppKit never delivers Cmd+C/V/X/A/Z to text fields, and the
        // View menu below powers the ⌘1…⌘9 / ⌘0 section shortcuts.
        setupMainMenu()

        // 2. Register status bar item FIRST so it survives even if window is closed
        setupStatusItem()

        // 3. Tasks: load stored tasks, re-arm pending reminders, start the due
        // scanner. A reminder banner click opens the panel on the Tasks tab.
        TaskStore.shared.load()
        TaskReminderManager.shared.onOpenTasks = { [weak self] in
            self?.openTasksTab()
        }
        TaskReminderManager.shared.start()

        // 4. Thermal: watch macOS thermal pressure + CPU load; alerts name the
        // hot process and the chat behind it. A banner click opens the Thermal
        // tab. Kept running so alerts fire even while the panel is hidden.
        ThermalMonitor.shared.onOpenThermal = { [weak self] in
            self?.openThermalTab()
        }
        ThermalMonitor.shared.start()

        // 5. Captures: screenshots & screen recordings with a send-to-chat
        // action. The panel hides itself while a still is taken and for the
        // whole recording, so the widget never shows up in its own captures.
        CaptureRecorder.shared.setPanelHidden = { [weak self] hidden in
            self?.setPanelHidden(hidden)
        }
        CaptureRecorder.shared.onRecordingChanged = { [weak self] recording in
            self?.statusView?.recording = recording
        }
        CaptureRecorder.shared.onRecordingFinished = { [weak self] url in
            guard let self else { return }
            AppState.shared.selectedTab = .captures
            if url != nil { CaptureStore.shared.rescan() }
            self.showPanel()
        }

        // 6. Create and show the panel
        panelController = FloatingPanelController()
        panelController?.showWindow(nil)
        panelController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 7. Menu bar glance — refresh every 30s while the widget runs
        refreshStatusItem()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
    }

    /// Installs the app menu (Quit) and the standard Edit menu so clipboard
    /// shortcuts reach the panel's text fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ZCode Widget",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // View menu: ⌘1…⌘9 / ⌘0 switch sections (shows the panel if hidden).
        // Key equivalents are single characters, so the 10th tab wraps to "0".
        // Tabs beyond ten (rawValue >= 10, e.g. Design) get no shortcut — the
        // modulo would otherwise collide with ⌘1.
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        for tab in SidebarTab.allCases {
            let item = NSMenuItem(title: tab.title,
                                  action: #selector(selectTab(_:)),
                                  keyEquivalent: tab.rawValue < 10 ? String((tab.rawValue + 1) % 10) : "")
            item.tag = tab.rawValue
            item.target = self
            viewMenu.addItem(item)
        }
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        guard let tab = SidebarTab(rawValue: sender.tag) else { return }
        Task { @MainActor in
            AppState.shared.selectedTab = tab
            showPanel()
        }
    }

    /// Opens the panel on the Tasks tab (menu item, banner click, context menu).
    @objc private func openTasksTab() {
        Task { @MainActor in
            AppState.shared.selectedTab = .tasks
            showPanel()
        }
    }

    /// Opens the panel on the Thermal tab (thermal banner click, context menu).
    @objc private func openThermalTab() {
        Task { @MainActor in
            AppState.shared.selectedTab = .thermal
            showPanel()
        }
    }

    /// Opens the panel on the Captures tab.
    @objc private func openCapturesTab() {
        Task { @MainActor in
            AppState.shared.selectedTab = .captures
            showPanel()
        }
    }

    /// Stops an in-flight screen recording (menu-bar context menu).
    @objc private func stopRecording() {
        CaptureRecorder.shared.stopRecording()
    }

    /// Hides/shows the panel around captures; the panel comes back exactly as
    /// it was, so a hidden widget stays hidden after a background capture.
    private var wasPanelVisibleBeforeCapture = true
    private func setPanelHidden(_ hidden: Bool) {
        guard let window = panelController?.window else { return }
        if hidden {
            wasPanelVisibleBeforeCapture = window.isVisible
            window.orderOut(nil)
        } else if wasPanelVisibleBeforeCapture {
            wasPanelVisibleBeforeCapture = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPanel() {
        panelController?.showWindow(nil)
        panelController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - keep the status bar item alive
        return false
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let view = StatusItemView()
        view.onLeftClick = { [weak self] in
            self?.refreshStatusItem()  // fresh numbers on click
            self?.togglePanel()
        }
        view.onRightClick = { [weak self] in
            self?.refreshStatusItem()
            self?.showContextMenu()
        }
        statusItem?.view = view
        statusView = view
    }

    /// Menu bar glance: "Z 1.2M" with today's tokens; orange at ≥80% of the
    /// daily budget, red when exceeded. Budget 0 = plain label color. The
    /// tooltip also reports tasks due within 24 h.
    private func refreshStatusItem() {
        let settings = WidgetSettingsStore()
        settings.load()
        let today = (try? TokenUsageRepository().todayTokens()) ?? 0
        let dueCount = TaskStore.shared.dueSoonCount

        let color: NSColor
        if settings.dailyBudget > 0 {
            let ratio = Double(today) / Double(settings.dailyBudget)
            if ratio >= 1 {
                color = .systemRed
            } else if ratio >= 0.8 {
                color = .systemOrange
            } else {
                color = .labelColor
            }
        } else {
            color = .labelColor
        }

        statusView?.text = Self.formatCompact(today)
        statusView?.tint = color
        var tip = settings.dailyBudget > 0
            ? "\(Self.formatCompact(today)) of \(Self.formatCompact(settings.dailyBudget)) tokens today"
            : "\(Self.formatCompact(today)) tokens today"
        if dueCount > 0 {
            tip += dueCount == 1 ? " · 1 task due" : " · \(dueCount) tasks due"
        }
        statusView?.toolTip = tip
        if let width = statusView?.intrinsicContentSize.width {
            statusItem?.length = width + 4
        }
    }

    private static func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }

    private func togglePanel() {
        guard let window = panelController?.window else { return }
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Recording shortcut — stop from the menu bar while the panel is hidden.
        if CaptureRecorder.shared.isRecording {
            menu.addItem(NSMenuItem(title: "⏹ Stop screen recording",
                                    action: #selector(stopRecording),
                                    keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }

        // Machine-hot shortcut — one click to the Thermal tab.
        if ThermalMonitor.shared.isHot {
            menu.addItem(NSMenuItem(title: "🔥 Mac running hot — open Thermal",
                                    action: #selector(openThermalTab),
                                    keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }

        // Tasks quick glance — each due task opens the panel on the Tasks tab.
        let dueTasks = TaskStore.shared.dueSoonTasks
        if !dueTasks.isEmpty {
            for task in dueTasks.prefix(6) {
                let item = NSMenuItem(title: task.title,
                                      action: #selector(openTasksTab),
                                      keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            if dueTasks.count > 6 {
                let more = NSMenuItem(title: "…and \(dueTasks.count - 6) more", action: nil, keyEquivalent: "")
                more.isEnabled = false
                menu.addItem(more)
            }
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem(title: "Show ZCode Widget", action: #selector(openWidget), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Hide ZCode Widget", action: #selector(hideWidget), keyEquivalent: "h"))
        if !dueTasks.isEmpty {
            menu.addItem(NSMenuItem(title: "Open Tasks", action: #selector(openTasksTab), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ZCode Widget", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem?.popUpMenu(menu)
    }

    @objc private func openWidget() {
        showPanel()
    }

    @objc private func hideWidget() {
        panelController?.window?.orderOut(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// Custom status item view: draws "Z <today's tokens>" with an explicit color
/// (label / orange / red). A plain NSStatusBarButton ignores title colors, so
/// the text is drawn directly. While a screen recording runs, a red dot is
/// drawn in front of the label.
private final class StatusItemView: NSView {
    var text = "" { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var tint: NSColor = .labelColor { didSet { needsDisplay = true } }
    var recording = false { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        let width = ("Z \(text)" as NSString).size(withAttributes: Self.textAttributes).width
        return NSSize(width: ceil(width) + (recording ? 22 : 14), height: 24)
    }

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
    ]

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: tint,
        ]
        if recording {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: bounds.midY - 3.5, width: 7, height: 7)).fill()
        }
        let string = "Z \(text)" as NSString
        let size = string.size(withAttributes: attrs)
        let x = recording ? 16 : (bounds.width - size.width) / 2
        string.draw(
            at: NSPoint(x: x, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) { onLeftClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}
