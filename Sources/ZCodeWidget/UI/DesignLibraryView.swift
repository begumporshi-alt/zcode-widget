import SwiftUI
import AppKit

// MARK: - DesignLibraryView

struct DesignLibraryView: View {
    @StateObject private var library = DesignLibraryStore()
    @State private var toastMessage: String?
    @State private var searchText = ""
    @State private var tagFilter = "All"
    @State private var detailEntry: DesignEntry?
    @State private var editingEntry: DesignEntry?
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 8) {
            header
            chipRow
            if library.entries.isEmpty {
                emptyState
            } else {
                designList
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
        .sheet(item: $detailEntry) { entry in
            DesignDetailSheet(
                entry: entry,
                onEdit: {
                    detailEntry = nil
                    editingEntry = entry
                    showEditor = true
                },
                onCopyBrief: {
                    copyToPasteboard(DesignLibraryStore.briefMarkdown(for: entry))
                    showToast("Brief copied as Markdown")
                },
                onCopyHex: { hex in
                    copyToPasteboard(hex)
                    showToast("Copied \(hex)")
                }
            )
        }
        .sheet(isPresented: $showEditor) {
            if let entry = editingEntry {
                DesignEditorSheet(entry: entry) { saved in
                    library.upsert(saved)
                    showToast("Saved “\(saved.name)”")
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Search designs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(ZTheme.body)

            Button {
                editingEntry = DesignEntry(name: "")
                showEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .help("Add design direction")

            Button {
                library.restoreDefaults()
                showToast("Built-ins restored")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .help("Restore built-in design directions")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["All"] + library.allTags, id: \.self) { tag in
                    FilterChip(
                        title: tag == "All" ? "All" : tag.capitalized,
                        isSelected: tagFilter == tag
                    ) {
                        tagFilter = tag
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: List

    private var designList: some View {
        List {
            ForEach(filteredEntries) { entry in
                DesignRow(
                    entry: entry,
                    onOpen: { detailEntry = entry },
                    onCopyBrief: {
                        copyToPasteboard(DesignLibraryStore.briefMarkdown(for: entry))
                        showToast("Brief copied as Markdown")
                    },
                    onEdit: {
                        editingEntry = entry
                        showEditor = true
                    },
                    onDuplicate: {
                        let copy = library.duplicate(entry)
                        library.upsert(copy)
                        showToast("Duplicated “\(entry.name)”")
                    },
                    onDelete: {
                        library.remove(entry)
                        showToast("Deleted “\(entry.name)”")
                    },
                    onCopyHex: { hex in
                        copyToPasteboard(hex)
                        showToast("Copied \(hex)")
                    }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "paintpalette")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No design directions yet")
                .font(ZTheme.bodyMedium)
                .foregroundStyle(.secondary)
            Text("Add one with ＋, or restore the built-ins.")
                .font(ZTheme.micro)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var filteredEntries: [DesignEntry] {
        var result = library.sorted
        if tagFilter != "All" {
            result = result.filter { $0.tags.contains(tagFilter) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.tagline.localizedCaseInsensitiveContains(searchText)
                    || $0.brandFit.localizedCaseInsensitiveContains(searchText)
                    || $0.typography.localizedCaseInsensitiveContains(searchText)
                    || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        return result
    }

    // MARK: Actions

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - DesignRow

private struct DesignRow: View {
    let entry: DesignEntry
    let onOpen: () -> Void
    let onCopyBrief: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onCopyHex: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(ZTheme.bodySemibold)
                        .lineLimit(1)
                    if entry.isBuiltin {
                        Text("built-in")
                            .font(ZTheme.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if !entry.tagline.isEmpty {
                    Text(entry.tagline)
                        .font(ZTheme.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !entry.swatches.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(entry.swatches) { swatch in
                            SwatchDot(swatch: swatch, size: 14, onCopy: onCopyHex)
                        }
                    }
                }
                if !entry.typography.isEmpty {
                    Text(entry.typography)
                        .font(ZTheme.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !entry.tags.isEmpty {
                    Text(entry.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(ZTheme.micro)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                rowButton("doc.on.doc", "Copy brief as Markdown", onCopyBrief)
                rowButton("pencil", "Edit", onEdit)
                rowButton("plus.square.on.square", "Duplicate", onDuplicate)
                rowButton("trash", "Delete", onDelete)
            }
        }
        .padding(.vertical, 2)
    }

    private func rowButton(_ systemImage: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - DesignDetailSheet

private struct DesignDetailSheet: View {
    let entry: DesignEntry
    let onEdit: () -> Void
    let onCopyBrief: () -> Void
    let onCopyHex: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(entry.tagline)
                        .font(ZTheme.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !entry.swatches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Palette — click to copy")
                            HStack(spacing: 16) {
                                ForEach(entry.swatches) { swatch in
                                    SwatchDot(swatch: swatch, size: 26, showsName: true, onCopy: onCopyHex)
                                }
                            }
                        }
                    }
                    if !entry.typography.isEmpty { noteSection("Typography", entry.typography) }
                    if !entry.imagery.isEmpty { noteSection("Imagery", entry.imagery) }
                    if !entry.layout.isEmpty { noteSection("Layout", entry.layout) }

                    if !entry.brandFit.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Best for")
                            Text(entry.brandFit)
                                .font(ZTheme.body)
                        }
                    }

                    if ![entry.notesHome, entry.notesListing, entry.notesDetail, entry.notesCheckout]
                        .allSatisfy({ $0.isEmpty }) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Page applications")
                            pageNote("Home", entry.notesHome)
                            pageNote("Category / PLP", entry.notesListing)
                            pageNote("Product / PDP", entry.notesDetail)
                            pageNote("Cart / Checkout", entry.notesCheckout)
                        }
                    }

                    if !entry.uiNotes.isEmpty { noteSection("UI details", entry.uiNotes) }

                    if !entry.references.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: "References")
                            ForEach(entry.references) { ref in
                                if let url = ref.url, let link = URL(string: url) {
                                    Button {
                                        NSWorkspace.shared.open(link)
                                    } label: {
                                        Label(ref.name, systemImage: "arrow.up.right")
                                            .font(ZTheme.bodyMedium)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                    .help(url)
                                } else {
                                    Text(ref.name)
                                        .font(ZTheme.bodyMedium)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    onCopyBrief()
                } label: {
                    Label("Copy brief as Markdown", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 500, height: 580)
    }

    private func noteSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title)
            Text(text)
                .font(ZTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func pageNote(_ label: String, _ text: String) -> some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(ZTheme.bodyMedium)
                    .frame(width: 110, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(ZTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - DesignEditorSheet

private struct DesignEditorSheet: View {
    @State var entry: DesignEntry
    let onSave: (DesignEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tagsText: String

    init(entry: DesignEntry, onSave: @escaping (DesignEntry) -> Void) {
        _entry = State(initialValue: entry)
        _tagsText = State(initialValue: entry.tags.joined(separator: ", "))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.name.isEmpty ? "New design direction" : "Edit \(entry.name)")
                        .font(ZTheme.title)

                    TextField("Name", text: $entry.name)
                        .textFieldStyle(.roundedBorder)
                        .font(ZTheme.body)

                    TextField("Tagline", text: $entry.tagline)
                        .textFieldStyle(.roundedBorder)
                        .font(ZTheme.body)

                    TextField("Tags (comma separated: minimal, boho…)", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                        .font(ZTheme.body)

                    TextField("Best for (brand fit)", text: $entry.brandFit)
                        .textFieldStyle(.roundedBorder)
                        .font(ZTheme.body)

                    // Palette
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionHeader(title: "Palette")
                            Spacer()
                            Button {
                                entry.swatches.append(DesignSwatch(name: "", hex: "#888888"))
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Add color")
                        }
                        ForEach($entry.swatches) { $swatch in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: swatch.hex) ?? Color(nsColor: .lightGray))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(ZTheme.hairline))
                                TextField("Name", text: $swatch.name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(ZTheme.micro)
                                TextField("#Hex", text: $swatch.hex)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(width: 90)
                                Button {
                                    entry.swatches.removeAll { $0.id == swatch.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove color")
                            }
                        }
                    }

                    field("Typography (display + body, tracking)", text: $entry.typography, height: 44)
                    field("Imagery approach", text: $entry.imagery, height: 44)
                    field("Layout feel", text: $entry.layout, height: 44)
                    field("Home page", text: $entry.notesHome, height: 44)
                    field("Category / PLP", text: $entry.notesListing, height: 44)
                    field("Product / PDP", text: $entry.notesDetail, height: 44)
                    field("Cart / Checkout", text: $entry.notesCheckout, height: 44)
                    field("UI details (buttons, nav, whitespace, mobile)", text: $entry.uiNotes, height: 70)

                    // References
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionHeader(title: "References")
                            Spacer()
                            Button {
                                entry.references.append(DesignReference(name: ""))
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Add reference")
                        }
                        ForEach($entry.references) { $ref in
                            HStack(spacing: 6) {
                                TextField("Name", text: $ref.name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(ZTheme.micro)
                                TextField("https://…", text: $ref.url.unwrap())
                                    .textFieldStyle(.roundedBorder)
                                    .font(ZTheme.micro)
                                Button {
                                    entry.references.removeAll { $0.id == ref.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove reference")
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var saved = entry
                    saved.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.tags = tagsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 660)
    }

    private func field(_ placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(placeholder)
                .font(ZTheme.micro)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(ZTheme.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: ZTheme.radiusSmall, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ZTheme.radiusSmall, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15))
                )
        }
    }
}

// MARK: - Optional binding helper

private extension Binding where Value == String? {
    /// Lets a TextField bind to an optional String (e.g. reference URLs),
    /// treating nil as empty.
    func unwrap() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
