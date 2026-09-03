import SwiftUI
import AppKit

enum SidebarTab: Int, CaseIterable, Identifiable {
    case tokens, skills, plugins, providers, report, prompts, database, tasks

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tokens: "Tokens"
        case .skills: "Skills"
        case .plugins: "Plugins"
        case .providers: "Providers"
        case .report: "Report"
        case .prompts: "Prompts"
        case .database: "Database"
        case .tasks: "Tasks"
        }
    }

    var icon: String {
        switch self {
        case .tokens: "chart.bar.fill"
        case .skills: "wand.and.stars"
        case .plugins: "puzzlepiece.extension.fill"
        case .providers: "server.rack"
        case .report: "square.and.arrow.up"
        case .prompts: "text.quote"
        case .database: "cylinder.split.1x2"
        case .tasks: "checklist"
        }
    }
}

struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var hoveredTab: SidebarTab?
    @StateObject private var ticker = ActivityTicker()
    @StateObject private var settings = WidgetSettingsStore()
    @ObservedObject private var taskStore = TaskStore.shared
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }

            Divider()

            // Ticker strip + bottom-right resize grip (shares the same
            // background so the grip reads as the panel's corner).
            HStack(spacing: 0) {
                ActivityTickerBar(ticker: ticker)
                ResizeGrip()
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
            }
        }
        // Grows with the window; the resize grip is the only way to change the
        // size of this borderless panel.
        .frame(minWidth: PanelMetrics.minSize.width, minHeight: PanelMetrics.minSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settings.load()
            taskStore.load()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand
            HStack(spacing: 7) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("ZCode Widget")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)

            Divider()

            // Scrollable nav list — future-proof for more sections
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarTab.allCases) { tab in
                        sidebarItem(tab)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            Divider()

            // Footer: settings, hide, quit
            HStack(spacing: 6) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")

                Button(action: hideWidget) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide to menu bar (Z icon)")

                Spacer(minLength: 0)

                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit ZCode Widget")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 132)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarItem(_ tab: SidebarTab) -> some View {
        let isSelected = appState.selectedTab == tab
        let isHovered = hoveredTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { appState.selectedTab = tab }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15)
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if tab == .tasks {
                    if taskStore.dueSoonCount > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                            Text(taskStore.dueSoonCount > 9 ? "9+" : "\(taskStore.dueSoonCount)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 15, height: 15)
                        .help("Tasks due soon")
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14)
                          : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
        .help(tab.title)
    }

    // MARK: Content

    private var content: some View {
        ZStack {
            switch appState.selectedTab {
            case .tokens: TokensView()
            case .skills: SkillsView()
            case .plugins: PluginsView()
            case .providers: ProvidersView()
            case .report: ReportView()
            case .prompts: PromptsView()
            case .database: DatabaseView()
            case .tasks: TasksView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(appState.selectedTab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.12), value: appState.selectedTab)
    }

    private func hideWidget() {
        // Find the widget window specifically (it has a distinctive title)
        if let window = NSApp.windows.first(where: { $0.title == "ZCode Widget" }) {
            window.orderOut(nil)
        } else if let window = NSApp.keyWindow {
            window.orderOut(nil)
        } else {
            // Fallback: hide all windows
            for window in NSApp.windows where window.isVisible {
                window.orderOut(nil)
            }
        }
    }
}
