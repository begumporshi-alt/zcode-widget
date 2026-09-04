import SwiftUI
import AppKit
import AVFoundation
import AVKit

/// Captures tab — screenshots & screen recordings with an in-widget gallery.
/// A selected screenshot can be sent into a live ZCode chat (ChatSender); if
/// ZCode doesn't accept the auto-send the image is copied instead.
struct CapturesView: View {
    @ObservedObject private var store = CaptureStore.shared
    @ObservedObject private var recorder = CaptureRecorder.shared
    @ObservedObject private var options = CaptureOptionsStore.shared

    @State private var selectedItem: CaptureStore.CaptureItem?
    @State private var previewImage: NSImage?
    @State private var previewDuration: TimeInterval?
    @State private var busy = false
    @State private var targets: [ChatSender.ChatTarget] = []
    @State private var targetSessionID: String?
    @State private var toastMessage: String?
    @State private var showAreaEditor = false
    @State private var editorReference: NSImage?
    @State private var micStatus: AVAuthorizationStatus = .notDetermined

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
                if recorder.grantedWhileRunning {
                    relaunchCard
                }
                captureBar
                if recorder.isRecording {
                    Text("Recording — the widget hid itself so it stays out of the video. Stop it here or from the menu-bar icon.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                optionsSection
                if recorder.isProcessingBlur {
                    processingRow
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
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if let notice = recorder.consumeNotice() {
                showToast(notice)
            }
        }
        .onChange(of: recorder.pendingNotice) { notice in
            guard let notice else { return }
            showToast(notice)
            _ = recorder.consumeNotice()
        }
        .sheet(isPresented: $showAreaEditor) {
            if let editorReference {
                PrivacyAreaEditorSheet(reference: editorReference,
                                       existingRegions: options.blurRegions,
                                       style: options.blurStyle) { regions in
                    options.setBlurRegions(regions)
                }
            }
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
            Text("Captures need macOS Screen Recording permission — without it the widget can only photograph its own panel. Grant it for ZCodeWidget (Touch ID or your password may be asked). If ZCodeWidget already shows ON in that list but this card stays, toggle it OFF and back ON — every newly built widget needs a fresh grant. Afterwards quit & relaunch the widget so the grant takes effect.")
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

                Button {
                    CaptureRecorder.relaunchApp()
                } label: {
                    Label("Relaunch", systemImage: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
                .help("Quit and reopen the widget (needed after granting)")
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    /// Shown when the grant arrives while the widget is already running:
    /// macOS activates Screen Recording only on launch, so a relaunch is
    /// needed before captures produce anything.
    private var relaunchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permission granted — relaunch to activate", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("Screen Recording was just enabled while the widget was running. macOS only applies it on launch — quit & reopen the widget before capturing.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                CaptureRecorder.relaunchApp()
            } label: {
                Label("Relaunch now", systemImage: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14))
            .cornerRadius(6)
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
                    startRecording()
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

    // MARK: Privacy & voice-over options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy & audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Blur sensitive areas", isOn: Binding(
                get: { options.blurEnabled },
                set: { options.setBlurEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 11.5, weight: .medium))

            if options.blurEnabled {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { options.blurStyle },
                        set: { options.setBlurStyle($0) }
                    )) {
                        Text("Blur").tag(PrivacyRedactor.Style.blur)
                        Text("Pixelate").tag(PrivacyRedactor.Style.pixelate)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 118)

                    Button {
                        openAreaEditor()
                    } label: {
                        Label(options.blurRegions.isEmpty ? "Edit areas…" : "Edit areas… (\(options.blurRegions.count))",
                              systemImage: "rectangle.dashed")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .cornerRadius(6)
                    .disabled(!recorder.isAuthorized)
                    .help("Draw boxes over anything sensitive")

                    Spacer(minLength: 0)
                }

                Text(options.blurRegions.isEmpty
                     ? "No areas yet — draw boxes over anything sensitive and every capture gets redacted there."
                     : "Areas are redacted from all screenshots and recordings of the chat screen. Boxes stay fixed on the screen (they don't follow moved windows). Unblurred originals are never kept.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Voice-over narration (microphone)", isOn: Binding(
                get: { options.voiceOverEnabled },
                set: { setVoiceOver($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 11.5, weight: .medium))

            if options.voiceOverEnabled {
                micHint
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var micHint: some View {
        if micStatus == .denied || micStatus == .restricted {
            HStack(spacing: 6) {
                Label("Microphone denied — recordings will be silent.", systemImage: "mic.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                } label: {
                    Text("System Settings…")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("Your mic records alongside the screen while a recording runs. macOS asks for permission the first time.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var processingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Applying privacy blur… \(Int((recorder.processingProgress ?? 0) * 100))%")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func setVoiceOver(_ on: Bool) {
        options.setVoiceOverEnabled(on)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if on, micStatus == .notDetermined {
            // Flipping the toggle is the "allow it" moment — ask right away so
            // the first recording already carries the narration.
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        }
    }

    private func startRecording() {
        guard options.voiceOverEnabled else {
            recorder.startRecording(includeAudio: false)
            return
        }
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            recorder.startRecording(includeAudio: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    if granted {
                        recorder.startRecording(includeAudio: true)
                    } else {
                        showToast("Microphone denied — recording without voice-over")
                        recorder.startRecording(includeAudio: false)
                    }
                }
            }
        default:
            showToast("Microphone denied — recording without voice-over")
            recorder.startRecording(includeAudio: false)
        }
    }

    private func openAreaEditor() {
        guard recorder.isAuthorized else { return }
        editorReference = nil
        // The reference shot hides the panel first, so the areas are drawn on
        // the bare screen the user actually wants to capture.
        recorder.captureReference { image in
            if let image {
                editorReference = image
                showAreaEditor = true
            } else {
                showToast("Couldn't grab a reference screenshot")
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
