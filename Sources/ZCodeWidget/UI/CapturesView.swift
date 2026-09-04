import SwiftUI
import AppKit
import AVKit

/// Captures tab — screenshots & screen recordings with an in-widget gallery.
/// A selected screenshot can be sent into a live ZCode chat (ChatSender); if
/// ZCode doesn't accept the auto-send the image is copied instead.
struct CapturesView: View {
    @ObservedObject private var store = CaptureStore.shared
    @ObservedObject private var recorder = CaptureRecorder.shared

    @State private var selectedItem: CaptureStore.CaptureItem?
    @State private var previewImage: NSImage?
    @State private var previewDuration: TimeInterval?
    @State private var busy = false
    @State private var targets: [ChatSender.ChatTarget] = []
    @State private var targetSessionID: String?
    @State private var toastMessage: String?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recorder.isAuthorized {
                    permissionCard
                }
                captureBar
                if recorder.isRecording {
                    Text("Recording — the widget hid itself so it stays out of the video. Stop it here or from the menu-bar icon.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                galleryHeader
                gallery
                Divider()
                detailPanel
                footerNote
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: toastMessage)
        .onAppear {
            store.rescan()
            loadTargets()
        }
        .onChange(of: recorder.isRecording) { _ in
            if !recorder.isRecording { store.rescan() }
        }
        .task(id: selectedItem?.id) {
            previewImage = nil
            previewDuration = nil
            guard let item = selectedItem else { return }
            if item.kind == .image {
                previewImage = await store.preview(for: item)
            } else {
                previewDuration = await store.duration(for: item)
            }
        }
    }

    // MARK: Permission card

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen Recording permission needed", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("Captures need macOS Screen Recording permission — without it the widget can only photograph its own panel. Grant it once (macOS may ask for your Touch ID or password), then quit and relaunch the widget from the menu bar (Z icon → Quit).")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    recorder.requestAccess()
                } label: {
                    Label("Request permission", systemImage: "camera.fill")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14))
                .cornerRadius(6)

                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                } label: {
                    Label("Open System Settings…", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: Capture bar

    private var captureBar: some View {
        HStack(spacing: 8) {
            pillButton("Screen", icon: "display", disabled: busy || !recorder.isAuthorized) {
                runCapture(.chatScreen)
            }
            pillButton("Window", icon: "macwindow", disabled: busy || !recorder.isAuthorized) {
                runCapture(.chatWindow)
            }
            if recorder.isRecording {
                Button {
                    recorder.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.red)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                pillButton("Record", icon: "record.circle", tint: .red, disabled: busy || !recorder.isAuthorized) {
                    recorder.startRecording()
                }
            }
            Spacer(minLength: 0)
            if recorder.isCapturing {
                ProgressView()
                    .controlSize(.small)
                    .help("Capturing…")
            } else {
                Button {
                    store.openFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open the captures folder (~/.zcode/captures)")
            }
        }
    }

    private func pillButton(_ title: String,
                            icon: String,
                            tint: Color = .accentColor,
                            disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14))
        .cornerRadius(6)
        .disabled(disabled)
    }

    private func runCapture(_ mode: CaptureRecorder.Mode) {
        busy = true
        recorder.capture(mode) { url in
            busy = false
            if let url {
                selectedItem = store.items.first { $0.url == url }
                showToast("Saved to ~/.zcode/captures")
            } else if !recorder.isAuthorized {
                showToast("Screen Recording permission is needed first")
            } else {
                showToast("Couldn't capture the screen")
            }
        }
    }

    // MARK: Gallery

    private var galleryHeader: some View {
        HStack {
            Text("Captures")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            }
            Spacer(minLength: 0)
        }
    }

    private var gallery: some View {
        Group {
            if store.items.isEmpty {
                Text("No captures yet — grab a screenshot or start a recording above. Files live in ~/.zcode/captures.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(store.items) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                selectedItem = item
                            }
                        } label: {
                            CaptureThumb(item: item,
                                         isSelected: selectedItem == item)
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
            }
        }
    }

    // MARK: Detail

    private var detailPanel: some View {
        Group {
            if let item = selectedItem {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(Self.timeFormatter.string(from: item.createdAt))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Text(item.sizeLabel)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    previewArea(item)

                    if item.kind == .image {
                        sendRow(item)
                    } else {
                        HStack(spacing: 8) {
                            pillButton("Copy video", icon: "doc.on.doc", disabled: false) {
                                ChatSender.copyVideoToClipboard(item.url)
                                showToast("Video file copied — attach it in your chat")
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            ChatSender.copyImageToClipboard(item.url)
                            showToast("Image copied — ⌘V in your ZCode chat")
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                        .help("Copy the image to the clipboard")

                        Button {
                            store.reveal(item)
                        } label: {
                            Label("Reveal", systemImage: "magnifyingglass")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                        .help("Show in Finder")

                        Spacer(minLength: 0)

                        Button {
                            if store.trash(item) {
                                selectedItem = nil
                                showToast("Moved to Trash")
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                        .help("Move to Trash")
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
            } else {
                Text("Select a capture above to preview it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func previewArea(_ item: CaptureStore.CaptureItem) -> some View {
        if item.kind == .image {
            Group {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 150)
            .frame(minHeight: 60)
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)
        } else {
            VideoPlayerView(url: item.url)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 150)
                .cornerRadius(6)
                .overlay(alignment: .bottomTrailing) {
                    let label = CaptureStore.durationLabel(previewDuration)
                    if !label.isEmpty {
                        Text(label)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
        }
    }

    // MARK: Send to chat

    private var selectedTarget: ChatSender.ChatTarget? {
        targets.first { $0.sessionID == targetSessionID }
    }

    private func loadTargets() {
        targets = ChatSender.recentChats(limit: 5)
        if targetSessionID == nil || !targets.contains(where: { $0.sessionID == targetSessionID }) {
            targetSessionID = targets.first?.sessionID
        }
    }

    private func sendRow(_ item: CaptureStore.CaptureItem) -> some View {
        HStack(spacing: 8) {
            Button {
                sendSelected(item)
            } label: {
                Label("Send to chat", systemImage: "paperplane.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(busy ? Color.accentColor.opacity(0.5) : Color.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(busy || selectedTarget == nil)

            Menu {
                ForEach(targets) { target in
                    Button {
                        targetSessionID = target.sessionID
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.displayLabel).lineLimit(1)
                            if !target.subLabel.isEmpty {
                                Text(target.subLabel).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if target.sessionID == targetSessionID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                if targets.isEmpty {
                    Button("No recent ZCode chats", action: {}).disabled(true)
                }
                Divider()
                Button("Refresh chat list") { loadTargets() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9.5))
                    Text(selectedTarget?.displayLabel ?? "Choose chat")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: 150, alignment: .leading)
            .fixedSize()
            .help("The ZCode chat the capture is sent into")

            Spacer(minLength: 0)
        }
    }

    private func sendSelected(_ item: CaptureStore.CaptureItem) {
        guard let target = selectedTarget else { return }
        busy = true
        ChatSender.sendImage(item.url, to: target) { report in
            busy = false
            switch report.outcome {
            case .sent:
                showToast("Sent to '\(report.chatLabel)'")
            case .discarded(let reason), .copied(let reason):
                showToast("Not auto-sent (\(reason)) — image copied, ⌘V in ZCode")
            case .notAnImage:
                showToast("Only screenshots can be sent directly")
            case .noChats:
                showToast("No recent ZCode chats found")
            }
        }
    }

    // MARK: Footer

    private var footerNote: some View {
        Text("Captures are stored in ~/.zcode/captures. \"Send to chat\" writes into the chosen chat's own input queue (the same one the ZCode UI uses); if ZCode doesn't accept the message within ~20 s, the image is copied to the clipboard instead.")
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation { toastMessage = nil }
        }
    }
}

/// One gallery tile. Loads its thumbnail + duration lazily.
private struct CaptureThumb: View {
    let item: CaptureStore.CaptureItem
    let isSelected: Bool

    @ObservedObject private var store = CaptureStore.shared
    @State private var thumb: NSImage?
    @State private var duration: TimeInterval?

    var body: some View {
        Group {
            if let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay {
                        Image(systemName: item.kind == .image ? "photo" : "film")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.55, contentMode: .fit)
        .clipped()
        .overlay {
            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if item.kind == .video {
                let label = CaptureStore.durationLabel(duration)
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(3)
                        .padding(3)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task(id: item.id) {
            thumb = await store.thumbnail(for: item)
            if item.kind == .video {
                duration = await store.duration(for: item)
            }
        }
    }
}

/// AVPlayerView bridge — SwiftUI's VideoPlayer needs the player kept alive,
/// so the representable owns it through a coordinator.
private struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    final class Holder {
        var player: AVPlayer?
    }

    func makeCoordinator() -> Holder { Holder() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        let player = AVPlayer(url: url)
        context.coordinator.player = player
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let current = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        guard current != url else { return }
        let player = AVPlayer(url: url)
        context.coordinator.player = player
        nsView.player = player
    }
}
