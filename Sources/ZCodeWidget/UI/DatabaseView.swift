import SwiftUI
import AppKit

// MARK: - DatabaseViewModel

@MainActor
final class DatabaseViewModel: ObservableObject {
    @Published var projects: [DbProject] = []
    @Published var isLoading = false
    @Published var selectedDirectory: String?

    private let scanner = ProjectDbScanner()
    private let settings = WidgetSettingsStore()

    var selectedProject: DbProject? {
        guard let dir = selectedDirectory else { return nil }
        return projects.first { $0.directory == dir }
    }

    func ensureLoaded() {
        if projects.isEmpty && !isLoading {
            refresh()
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        settings.load()
        let pinned = settings.pinnedProjectDirs
        let scan = scanner
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                scan.scan(pinnedDirs: pinned)
            }.value
            self.projects = result
            self.isLoading = false
        }
    }

    func addPinnedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Track in Database tab"
        panel.message = "Choose a project folder to track (migrations, RLS, triggers…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = (url.path as NSString).standardizingPath
        guard !settings.pinnedProjectDirs.contains(path) else { return }
        settings.load()
        guard !settings.pinnedProjectDirs.contains(path) else { return }
        settings.pinnedProjectDirs.append(path)
        settings.save()
        refresh()
    }

    func removePinnedFolder() {
        guard let dir = selectedDirectory else { return }
        settings.load()
        settings.pinnedProjectDirs.removeAll { $0 == dir }
        settings.save()
        selectedDirectory = nil
        refresh()
    }
}

// MARK: - DatabaseView

struct DatabaseView: View {
    @StateObject private var viewModel = DatabaseViewModel()

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                detail(project)
                    .id(project.directory)
            } else {
                list
            }
        }
        .onAppear { viewModel.ensureLoaded() }
    }

    // MARK: Project list

    private var list: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if viewModel.projects.isEmpty {
                emptyState
            } else {
                summaryLine
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.projects) { project in
                            projectRow(project)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Rescan projects")

            Button {
                viewModel.addPinnedFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Add a folder to track")

            Spacer(minLength: 0)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Database")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var summaryLine: some View {
        let tables = viewModel.projects.reduce(0) { $0 + $1.tables.count }
        let policies = viewModel.projects.reduce(0) { $0 + $1.policies.count }
        let functions = viewModel.projects.reduce(0) { $0 + $1.functions.count }
        let triggers = viewModel.projects.reduce(0) { $0 + $1.triggers.count }
        return Text("\(viewModel.projects.count) project\(viewModel.projects.count == 1 ? "" : "s") · \(tables) table\(tables == 1 ? "" : "s") · \(policies) RLS polic\(policies == 1 ? "y" : "ies") · \(functions) function\(functions == 1 ? "" : "s") · \(triggers) trigger\(triggers == 1 ? "" : "s")")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No database projects yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Projects you work on in ZCode are discovered automatically. You can also track any folder manually.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.addPinnedFolder()
            } label: {
                Label("Add folder…", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectRow(_ project: DbProject) -> some View {
        Button {
            viewModel.selectedDirectory = project.directory
        } label: {
            HStack(spacing: 8) {
                Image(systemName: project.hasDatabaseFiles ? "cylinder.split.1x2" : "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(project.hasDatabaseFiles ? Color.accentColor : Color.secondary)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(project.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if project.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(relativeDate(project.lastActivity))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(project.displayPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(project.countSummary)
                        .font(.system(size: 9))
                        .foregroundStyle(project.hasDatabaseFiles ? Color.secondary : Color.gray)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(project.displayPath)
    }

    // MARK: Project detail

    private func detail(_ project: DbProject) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    viewModel.selectedDirectory = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to projects")

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(project.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if project.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(project.displayPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rescan")

                if project.isPinned {
                    Button {
                        viewModel.removePinnedFolder()
                    } label: {
                        Image(systemName: "pin.slash")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop tracking this folder")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if project.hasDatabaseFiles {
                        statRows(project)
                    } else {
                        Text("No database files found in this folder — no migrations, schema SQL, policies, functions or triggers.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }

                    if !project.connections.isEmpty {
                        sectionTitle("Connections · \(project.connections.count)")
                        ForEach(project.connections) { connection in
                            card {
                                HStack(spacing: 7) {
                                    Image(systemName: "bolt.horizontal.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(connection.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Text("from \(connection.source) — key names only, values are never read")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    if !project.tables.isEmpty {
                        sectionTitle("Tables & Schema · \(project.tables.count)")
                        ForEach(project.tables) { table in
                            card {
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(table.columns.prefix(40)) { column in
                                            HStack(spacing: 10) {
                                                Text(column.name)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                                Text(column.type)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        if table.columns.count > 40 {
                                            Text("+ \(table.columns.count - 40) more columns")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.top, 5)
                                    .padding(.leading, 2)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(table.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if table.rlsEnabled {
                                            Text("RLS")
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                        Spacer(minLength: 4)
                                        Text("\(table.columns.count) col\(table.columns.count == 1 ? "" : "s")")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !project.policies.isEmpty {
                        sectionTitle("RLS Policies · \(project.policies.count)")
                        ForEach(project.policies) { policy in
                            card {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(policy.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(policySubline(policy))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if !project.functions.isEmpty {
                        sectionTitle("Functions · \(project.functions.count)")
                        ForEach(project.functions.prefix(150)) { function in
                            card {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(function.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !function.details.isEmpty {
                                        Text(function.details)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }

                    if !project.triggers.isEmpty {
                        sectionTitle("Triggers · \(project.triggers.count)")
                        ForEach(project.triggers.prefix(150)) { trigger in
                            card {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(trigger.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(trigger.details)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if !project.docs.isEmpty {
                        sectionTitle("Blueprints & Docs · \(project.docs.count)")
                        ForEach(project.docs.prefix(24)) { doc in
                            card {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(doc.title)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        if !doc.summary.isEmpty {
                                            Text(doc.summary)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    docBadge(doc)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func statRows(_ project: DbProject) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatCard(title: "Tables", value: "\(project.tables.count)", color: .blue)
                StatCard(title: "RLS Policies", value: "\(project.policies.count)", color: .green)
                StatCard(title: "Functions", value: "\(project.functions.count)", color: .orange)
            }
            HStack(spacing: 8) {
                StatCard(title: "Triggers", value: "\(project.triggers.count)", color: .purple)
                StatCard(title: "Migrations", value: "\(project.migrationFileCount)", color: .teal)
                StatCard(title: "Connections", value: "\(project.connections.count)", color: .pink)
            }
        }
    }

    // MARK: Shared bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(7)
    }

    private func policySubline(_ policy: DbPolicyInfo) -> String {
        var text = "ON \(policy.table) · FOR \(policy.command)"
        if !policy.roles.isEmpty {
            text += " · to " + policy.roles.joined(separator: ", ")
        }
        return text
    }

    private func docBadge(_ doc: DbDocInfo) -> some View {
        HStack(spacing: 3) {
            if doc.tag == "blueprint" {
                Text("blueprint")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.indigo.opacity(0.15))
                    .cornerRadius(4)
            }
            Text(doc.kind == "memory" ? "memory" : "repo")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.07))
                .cornerRadius(4)
        }
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
