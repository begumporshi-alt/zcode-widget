import AppKit
import AVFoundation
import CoreGraphics

/// Screenshot + screen-recording engine for the Captures tab.
///
/// Screen capture needs macOS Screen Recording permission (there is no
/// Info.plist key; the system prompt appears on first request). Captures never
/// include the widget itself: the floating panel is hidden for the instant a
/// still is taken and for the whole recording, then restored by the app.
final class CaptureRecorder: NSObject, ObservableObject {
    static let shared = CaptureRecorder()

    enum Mode { case chatScreen, chatWindow }

    @Published private(set) var isRecording = false
    @Published private(set) var isCapturing = false
    /// Live Screen Recording permission, polled every 2 s. A plain computed
    /// property would only be re-read when some OTHER state re-renders the
    /// view — with an empty gallery and disabled capture buttons nothing else
    /// re-renders, so a grant made after launch never cleared the card.
    @Published private(set) var isAuthorized = CGPreflightScreenCaptureAccess()
    /// The grant arrived while this process was already running — macOS only
    /// activates Screen Recording on (re)launch, so captures need a relaunch.
    @Published private(set) var grantedWhileRunning = false
    /// Baking the privacy blur into a finished recording (post-processing).
    @Published private(set) var isProcessingBlur = false
    @Published private(set) var processingProgress: Double?
    /// View-facing notice shown as a toast by CapturesView (consumed on read).
    @Published private(set) var pendingNotice: String?

    /// Called on the main thread so the app can hide/show the floating panel.
    var setPanelHidden: ((Bool) -> Void)?
    /// Called on the main thread when the recording state flips (status-item dot).
    var onRecordingChanged: ((Bool) -> Void)?
    /// Called on the main thread when a recording finishes (or fails).
    var onRecordingFinished: ((URL?) -> Void)?

    private let captureQueue = DispatchQueue(label: "zcode-widget.capture", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "zcode-widget.recording")
    private var session: AVCaptureSession?
    private let movieOutput = AVCaptureMovieFileOutput()
    /// Set when a recording starts (main thread) and read when it finishes
    /// (session queue): the final gallery URL and the blur settings to bake
    /// in, if any. With blur active the session records to a hidden raw file
    /// (.rec-raw-…, skipped by rescan) which is deleted after processing.
    private var pendingFinalURL: URL?
    private var pendingBlur: CaptureOptionsStore.BlurSnapshot?

    private override init() {
        super.init()
        let authorizedAtLaunch = isAuthorized
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, Thread.isMainThread else { return }
            let now = CGPreflightScreenCaptureAccess()
            if now != self.isAuthorized {
                self.isAuthorized = now
                if now && !authorizedAtLaunch {
                    self.grantedWhileRunning = true
                }
            }
        }
    }

    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
        isAuthorized = CGPreflightScreenCaptureAccess()
    }

    /// Quits and reopens the widget — required after a mid-session Screen
    /// Recording grant (macOS activates the permission on app launch).
    static func relaunchApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: Stills

    /// Captures and saves a PNG into the captures folder; the panel is hidden
    /// around the shot. `completion` runs on the main thread with the file URL,
    /// or nil when the capture failed / permission is missing.
    @MainActor
    func capture(_ mode: Mode, completion: @escaping (URL?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }
        let blur = CaptureOptionsStore.shared.blurSnapshot()
        isCapturing = true
        setPanelHidden?(true)
        // Give the panel a beat to leave the screen before the window list is
        // read, so the widget never appears in its own capture.
        captureQueue.asyncAfter(deadline: .now() + 0.2) {
            let url = Self.performStillCapture(mode, blur: blur)
            DispatchQueue.main.async {
                Task { @MainActor in
                    self.isCapturing = false
                    self.setPanelHidden?(false)
                    if url != nil { CaptureStore.shared.rescan() }
                    completion(url)
                }
            }
        }
    }

    /// Grabs a full-screen reference image for the privacy-area editor —
    /// in memory only, never written to disk (it may contain exactly the
    /// sensitive content the areas are meant to hide).
    @MainActor
    func captureReference(completion: @escaping (NSImage?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }
        isCapturing = true
        setPanelHidden?(true)
        captureQueue.asyncAfter(deadline: .now() + 0.2) {
            let target = Self.captureTarget()
            let image = Self.captureImage(.chatScreen, target: target)
            DispatchQueue.main.async {
                Task { @MainActor in
                    self.isCapturing = false
                    self.setPanelHidden?(false)
                    completion(image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) })
                }
            }
        }
    }

    private nonisolated static func captureImage(_ mode: Mode, target: CaptureTarget) -> CGImage? {
        switch mode {
        case .chatScreen:
            return CGWindowListCreateImage(target.displayBounds,
                                           .optionOnScreenOnly,
                                           kCGNullWindowID,
                                           [.bestResolution])
        case .chatWindow:
            guard let windowID = target.windowID else { return nil }
            return CGWindowListCreateImage(target.windowBounds,
                                           .optionIncludingWindow,
                                           windowID,
                                           [.bestResolution, .boundsIgnoreFraming])
        }
    }

    private nonisolated static func performStillCapture(_ mode: Mode,
                                                        blur: CaptureOptionsStore.BlurSnapshot?) -> URL? {
        let target = Self.captureTarget()
        guard let captured = Self.captureImage(mode, target: target) else { return nil }
        var image = captured
        // Privacy blur: redact in memory BEFORE anything hits disk, so no
        // unredacted original is ever written.
        if let blur {
            let regions: [CGRect]
            switch mode {
            case .chatScreen:
                regions = blur.pixelRegions(forFullScreen: CGSize(width: captured.width, height: captured.height))
            case .chatWindow:
                regions = blur.pixelRegions(forWindow: target.windowBounds,
                                            displayBounds: target.displayBounds,
                                            imageSize: CGSize(width: captured.width, height: captured.height))
            }
            if let redacted = PrivacyRedactor.redact(captured, regions: regions, style: blur.style) {
                image = redacted
            }
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = CaptureStore.makeFileURL(kind: .image)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Recording

    @MainActor
    func startRecording(includeAudio: Bool) {
        guard !isRecording, isAuthorized else { return }
        let target = Self.captureTarget()
        let blur = CaptureOptionsStore.shared.blurSnapshot()
        let finalURL = CaptureStore.makeFileURL(kind: .video)
        // With blur active the session records to a hidden raw file first
        // (dot-prefixed files are skipped by rescan); the redacted export
        // takes the final name and the raw is hard-deleted afterwards.
        let recordURL = blur != nil ? CaptureStore.makeHiddenRawURL() : finalURL
        pendingFinalURL = finalURL
        pendingBlur = blur
        setRecording(true)
        setPanelHidden?(true)
        sessionQueue.async { [self] in
            beginRecording(displayID: target.displayID, outputURL: recordURL, includeAudio: includeAudio)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [self] in
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            } else {
                finishRecording(url: nil)
            }
        }
    }

    private func beginRecording(displayID: CGDirectDisplayID, outputURL: URL, includeAudio: Bool) {
        let newSession = AVCaptureSession()
        guard let input = AVCaptureScreenInput(displayID: displayID) else {
            finishRecording(url: nil)
            return
        }
        guard newSession.canAddInput(input), newSession.canAddOutput(movieOutput) else {
            finishRecording(url: nil)
            return
        }
        newSession.addInput(input)
        if includeAudio {
            // Voice-over narration: mic input is best-effort — a missing or
            // denied microphone must never kill the screen recording.
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               newSession.canAddInput(micInput) {
                newSession.addInput(micInput)
            }
        }
        newSession.addOutput(movieOutput)
        // Note: AVCaptureConnection.videoSettings is iOS-only; on macOS the
        // movie output encodes with its own defaults (H.264 at screen size).

        newSession.startRunning()
        guard newSession.isRunning, movieOutput.connection(with: .video) != nil else {
            newSession.stopRunning()
            finishRecording(url: nil)
            return
        }
        session = newSession
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        if !movieOutput.isRecording {
            // startRecording failed to arm — bail out cleanly.
            newSession.stopRunning()
            session = nil
            finishRecording(url: nil)
        }
    }

    private func finishRecording(url: URL?) {
        pendingBlur = nil
        pendingFinalURL = nil
        if let url, !FileManager.default.fileExists(atPath: url.path) {
            finishRecording(url: nil)
            return
        }
        DispatchQueue.main.async {
            Task { @MainActor in
                self.setRecording(false)
                self.setPanelHidden?(false)
                if url != nil { CaptureStore.shared.rescan() }
                self.onRecordingFinished?(url)
            }
        }
    }

    /// Bakes the privacy blur into a raw recording: export → final URL →
    /// hard-delete the unblurred raw. The recording state clears immediately
    /// (REC dot off, panel back); `onRecordingFinished` fires only once the
    /// redacted file is ready.
    private func processRawRecording(_ rawURL: URL,
                                     finalURL: URL,
                                     blur: CaptureOptionsStore.BlurSnapshot) {
        DispatchQueue.main.async {
            Task { @MainActor in
                self.setRecording(false)
                self.setPanelHidden?(false)
                self.isProcessingBlur = true
                self.processingProgress = 0
            }
        }
        Task<Void, Never> {
            let blurFailed: Bool
            do {
                try await PrivacyRedactor.processVideo(at: rawURL,
                                                        outputURL: finalURL,
                                                        normalizedRegions: blur.normalizedRegions,
                                                        style: blur.style) { progress in
                    Task { @MainActor in
                        self.processingProgress = progress
                    }
                }
                blurFailed = false
            } catch {
                blurFailed = true
            }
            if blurFailed {
                // Keep the recording (the user can delete it) rather than
                // lose it — but say loudly that it is NOT redacted.
                try? FileManager.default.removeItem(at: finalURL)
                try? FileManager.default.moveItem(at: rawURL, to: finalURL)
            } else {
                try? FileManager.default.removeItem(at: rawURL)
            }
            await MainActor.run {
                self.isProcessingBlur = false
                self.processingProgress = nil
                if blurFailed {
                    self.pendingNotice = "Blur processing failed — recording saved WITHOUT blur"
                }
                CaptureStore.shared.rescan()
                self.onRecordingFinished?(finalURL)
            }
        }
    }

    /// Returns (and clears) a pending view-facing notice.
    @MainActor
    func consumeNotice() -> String? {
        let notice = pendingNotice
        pendingNotice = nil
        return notice
    }

    private func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        onRecordingChanged?(recording)
    }

    // MARK: Capture target (background)

    private struct CaptureTarget {
        var windowID: CGWindowID?
        var windowBounds: CGRect
        var displayBounds: CGRect
        var displayID: CGDirectDisplayID
    }

    /// The ZCode chat window when one is on screen (otherwise the frontmost
    /// window of any other app). Its display is the full-screen capture target.
    private nonisolated static func captureTarget() -> CaptureTarget {
        let widgetOwners = Set(["ZCode Widget", "ZCodeWidget"])
        var zcodeWindow: [String: Any]?
        var fallbackWindow: [String: Any]?
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }
                guard let bounds = Self.windowBounds(from: info) else { continue }
                guard bounds.width > 120, bounds.height > 80 else { continue }
                let owner = info[kCGWindowOwnerName as String] as? String ?? ""
                if widgetOwners.contains(owner) { continue }
                if zcodeWindow == nil, owner == "ZCode" { zcodeWindow = info }
                if fallbackWindow == nil { fallbackWindow = info }
            }
        }
        if let chosen = zcodeWindow ?? fallbackWindow {
            let bounds = Self.windowBounds(from: chosen) ?? .zero
            let windowID = CGWindowID((chosen[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            return CaptureTarget(windowID: windowID,
                                 windowBounds: bounds,
                                 displayBounds: Self.displayContaining(bounds) ?? CGDisplayBounds(CGMainDisplayID()),
                                 displayID: Self.displayIDContaining(bounds) ?? CGMainDisplayID())
        }
        // Nothing worth capturing on screen — fall back to the main display.
        let main = CGMainDisplayID()
        return CaptureTarget(windowID: nil,
                             windowBounds: .zero,
                             displayBounds: CGDisplayBounds(main),
                             displayID: main)
    }

    /// kCGWindowBounds is a CFDictionary; route through NSDictionary so the
    /// toll-free bridge stays explicit.
    private nonisolated static func windowBounds(from info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    private nonisolated static func displayIDContaining(_ bounds: CGRect) -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(8, &ids, &count) == .success, count > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for i in 0..<Int(count) where CGDisplayBounds(ids[i]).contains(center) {
            return ids[i]
        }
        return nil
    }

    private nonisolated static func displayContaining(_ bounds: CGRect) -> CGRect? {
        guard let id = displayIDContaining(bounds) else { return nil }
        return CGDisplayBounds(id)
    }
}

extension CaptureRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        let failed = (error != nil)
        if failed {
            // Partial/failed recording — drop the file rather than show garbage.
            try? FileManager.default.removeItem(at: outputFileURL)
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session?.stopRunning()
            self.session = nil
            let blur = self.pendingBlur
            let finalURL = self.pendingFinalURL
            self.pendingBlur = nil
            self.pendingFinalURL = nil
            if failed {
                self.finishRecording(url: nil)
            } else if let blur, let finalURL {
                self.processRawRecording(outputFileURL, finalURL: finalURL, blur: blur)
            } else {
                self.finishRecording(url: outputFileURL)
            }
        }
    }
}
