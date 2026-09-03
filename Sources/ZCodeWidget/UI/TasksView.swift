import SwiftUI
import AppKit

extension TaskPriority {
    /// Accent color shown as a small dot next to the title.
    var dotColor: Color? {
        switch self {
        case .none: return nil
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - TasksView

struct TasksView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var editingTask: TaskItem?
    @State private var isCreating = false
    @State private var showCompleted = false
    @State private var toastMessage: String?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if store.tasks.isEmpty && store.loadError == nil {
                emptyState
            } else {
                taskList
            }
        }
        .onAppear {
            store.load()
            TaskReminderManager.shared.scanNow()
        }
        .sheet(isPresented: $isCreating) {
            TaskEditorSheet(task: nil) { saved in
                save(saved)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task) { saved in
                save(saved)
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(summaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(summaryHasDue ? .orange : .secondary)
                if let err = store.loadError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button {
                editingTask = nil
                isCreating = true
            } label: {
                Label("New", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .help("Add a task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summaryHasDue: Bool { store.overdueCount + store.dueTodayCount > 0 }

    private var summaryText: String {
        var parts: [String] = []
        if store.overdueCount > 0 { parts.append("\(store.overdueCount) overdue") }
        if store.dueTodayCount > 0 { parts.append("\(store.dueTodayCount) due today") }
        if parts.isEmpty {
            let open = store.openTasks.count
            return open == 1 ? "1 open task" : "\(open) open tasks"
        }
        return parts.joined(separator: " · ")
    }

    // MARK: List

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(store.openTasks) { task in
                    TaskRow(task: task,
                            onToggle: { toggle(task) },
                            onEdit: { editingTask = task },
                            onDelete: { delete(task) })
                }

                if !store.completedTasks.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showCompleted.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                            Text("Completed (\(store.completedTasks.count))")
                                .font(.system(size: 11, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    if showCompleted {
                        ForEach(store.completedTasks) { task in
                            TaskRow(task: task,
                                    onToggle: { toggle(task) },
                                    onEdit: { editingTask = task },
                                    onDelete: { delete(task) })
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No tasks yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Add a task with a due time and ZCode Widget will remind you.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func save(_ saved: TaskItem) {
        store.upsert(saved)
        TaskReminderManager.shared.taskDidChange(saved)
        TaskReminderManager.shared.scanNow()
    }

    private func toggle(_ task: TaskItem) {
        guard let updated = store.setCompleted(task.id, !task.completed) else { return }
        TaskReminderManager.shared.taskDidChange(updated)
    }

    private func delete(_ task: TaskItem) {
        store.delete(task.id)
        TaskReminderManager.shared.taskDeleted(task.id)
        withAnimation { toastMessage = "Deleted “\(task.title)”" }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    static func relativeText(_ date: Date, prefix: String) -> String {
        let text = relative.localizedString(for: date, relativeTo: Date())
        return "\(prefix)\(text)"
    }
}

// MARK: - TaskRow

private struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.completed ? Color.green : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.completed ? "Mark as not done" : "Mark as done")

            Button(action: onEdit) {
                HStack(spacing: 6) {
                    if let color = task.priority.dotColor {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .strikethrough(task.completed, color: .secondary)
                            .foregroundStyle(task.completed ? .secondary : .primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit task")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(7)
    }

    private var subtitle: String {
        if task.completed {
            if let done = task.completedAt {
                return "Done \(Self.relative.localizedString(for: done, relativeTo: Date()))"
            }
            return "Done"
        }
        if let due = task.dueDate {
            return TaskStore.dueText(for: due, formatter: Self.relative)
        }
        if !task.notes.isEmpty {
            return task.notes.replacingOccurrences(of: "\n", with: " ")
        }
        return "No due date"
    }

    private var subtitleColor: Color {
        if task.completed { return .secondary }
        guard let due = task.dueDate else { return .secondary }
        let now = Date()
        if due < now { return .red }
        if due < now.addingTimeInterval(3600) { return .orange }
        return .secondary
    }
}

// MARK: - TaskEditorSheet

private struct TaskEditorSheet: View {
    let task: TaskItem?
    let onSave: (TaskItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var hasDue = false
    @State private var dueDate: Date
    @State private var remind = false
    @State private var priority: TaskPriority
    @State private var notificationsDenied = false

    init(task: TaskItem?, onSave: @escaping (TaskItem) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDue = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())
        _remind = State(initialValue: task?.reminderEnabled ?? false)
        _priority = State(initialValue: task?.priority ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task == nil ? "New task" : "Edit task")
                .font(.system(size: 14, weight: .semibold))

            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(height: 56)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes (optional)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }

            Toggle("Due date", isOn: $hasDue)
                .font(.system(size: 12, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.small)

            if hasDue {
                DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .font(.system(size: 12))
                    .padding(.leading, 24)

                Toggle("Remind me at the due time", isOn: $remind)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.leading, 24)
                    .onChange(of: remind) { wantsReminder in
                        guard wantsReminder else { return }
                        TaskReminderManager.shared.requestAuthorizationIfNeeded { granted in
                            notificationsDenied = !granted
                            if !granted { remind = false }
                        }
                    }

                if notificationsDenied {
                    Text("Notifications are off for ZCode Widget — enable them in System Settings → Notifications.")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .padding(.leading, 24)
                }
            }

            Picker("Priority", selection: $priority) {
                ForEach(TaskPriority.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.system(size: 11))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(task == nil ? "Add" : "Save") {
                    onSave(buildItem())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 400, height: 330)
    }

    private func buildItem() -> TaskItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = task {
            var copy = existing
            copy.title = trimmedTitle
            copy.notes = notes
            copy.dueDate = hasDue ? dueDate : nil
            copy.reminderEnabled = hasDue && remind
            copy.priority = priority
            return copy
        }
        return TaskItem(title: trimmedTitle,
                        notes: notes,
                        dueDate: hasDue ? dueDate : nil,
                        reminderEnabled: hasDue && remind,
                        priority: priority)
    }
}
