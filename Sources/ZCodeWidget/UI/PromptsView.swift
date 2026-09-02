import SwiftUI
import AppKit

// MARK: - PromptsView

struct PromptsView: View {
    @StateObject private var library = PromptLibraryStore()
    @State private var mode = 0  // 0 = Enhancer, 1 = Library
    @State private var input = ""
    @State private var output = ""
    @State private var enhancedBy = ""
    @State private var isEnhancing = false
    @State private var toastMessage: String?
    @State private var searchText = ""
    @State private var categoryFilter = "All"
    @State private var editingPrompt: PromptEntry?
    @State private var showEditor = false

    private let enhancer = PromptEnhancer()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Enhancer").tag(0)
                Text("Library").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if mode == 0 {
                enhancerView
            } else {
                libraryView
            }
        }
        .onAppear {
            library.load()
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Enhancer

    private var enhancerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your prompt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $input)
                    .font(.system(size: 12))
                    .frame(height: 90)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                Button(action: enhance) {
                    HStack(spacing: 6) {
                        if isEnhancing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isEnhancing ? "Enhancing…" : "Enhance")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEnhancing)

                if !output.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    Text("Enhanced")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: .constant(output))
                        .font(.system(size: 12))
                        .frame(height: 110)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                    HStack {
                        if !enhancedBy.isEmpty {
                            Text(enhancedBy)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            copyToClipboard(output)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Button {
                            saveOutputToLibrary()
                        } label: {
                            Label("Save to library", systemImage: "plus.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }

                if let err = library.loadError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    // MARK: Library

    private var libraryView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search prompts", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Button {
                    editingPrompt = PromptEntry(title: "", category: "coding", content: "")
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .help("Add prompt")

                Button {
                    library.restoreDefaults()
                    showToast("Defaults restored")
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .help("Restore built-in prompts")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["All"] + PromptLibraryStore.categories, id: \.self) { cat in
                        Button {
                            categoryFilter = cat
                        } label: {
                            Text(cat == "All" ? "All" : cat.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(categoryFilter == cat ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .foregroundStyle(categoryFilter == cat ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            List {
                ForEach(filteredPrompts) { entry in
                    PromptRow(entry: entry) {
                        copyToClipboard(entry.content)
                        showToast("Copied “\(entry.title)”")
                    } onEdit: {
                        editingPrompt = entry
                        showEditor = true
                    } onDelete: {
                        library.remove(entry)
                        showToast("Deleted “\(entry.title)”")
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showEditor) {
            if let prompt = editingPrompt {
                PromptEditorSheet(prompt: prompt) { saved in
                    library.upsert(saved)
                    showToast("Saved “\(saved.title)”")
                }
            }
        }
    }

    private var filteredPrompts: [PromptEntry] {
        var result = library.sorted
        if categoryFilter != "All" {
            result = result.filter { $0.category == categoryFilter }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    // MARK: Actions

    private func enhance() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isEnhancing = true
        output = ""
        enhancedBy = ""
        Task {
            do {
                let result = try await enhancer.enhance(text)
                output = result.text
                enhancedBy = "via \(result.providerName) · \(result.model)"
            } catch {
                showToast("Enhance failed: \(error.localizedDescription)")
            }
            isEnhancing = false
        }
    }

    private func saveOutputToLibrary() {
        let firstLine = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init) ?? "Prompt"
        let title = String(firstLine.prefix(40))
        library.upsert(PromptEntry(title: title.isEmpty ? "Enhanced prompt" : title, category: "writing", content: output))
        showToast("Saved to library")
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - PromptRow

private struct PromptRow: View {
    let entry: PromptEntry
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if entry.isBuiltin {
                        Text("built-in")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(entry.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Copy")
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Edit")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PromptEditorSheet

private struct PromptEditorSheet: View {
    let prompt: PromptEntry
    let onSave: (PromptEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String
    @State private var category: String

    init(prompt: PromptEntry, onSave: @escaping (PromptEntry) -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        _title = State(initialValue: prompt.title)
        _content = State(initialValue: prompt.content)
        _category = State(initialValue: prompt.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title.isEmpty ? "New prompt" : "Edit prompt")
                .font(.system(size: 14, weight: .semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            Picker("Category", selection: $category) {
                ForEach(PromptLibraryStore.categories, id: \.self) { cat in
                    Text(cat.capitalized).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextEditor(text: $content)
                .font(.system(size: 12))
                .frame(height: 160)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(PromptEntry(
                        id: prompt.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        category: category,
                        isBuiltin: prompt.isBuiltin,
                        content: content
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420, height: 330)
    }
}
