import AppKit

/// Non-isolated path holder (static vars on a @MainActor class would be
/// actor-isolated — same pattern as CapturePaths).
enum CaptureOptionsPaths {
    static var settingsPath = NSHomeDirectory() + "/.zcode/widget-capture-settings.json"
}

/// Optional capture features — privacy blur areas and voice-over narration —
/// persisted to `~/.zcode/widget-capture-settings.json`. Everything is OFF by
/// default; a feature starts working the moment the user switches it on.
@MainActor
final class CaptureOptionsStore: ObservableObject {
    static let shared = CaptureOptionsStore()

    /// A redaction area, normalized (0…1) against the captured display's
    /// bounds, so it survives resolution and backing-scale changes.
    struct BlurRegion: Codable, Identifiable, Equatable {
        var id = UUID()
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    /// Plain-value snapshot of the blur settings, handed to the recorder's
    /// background queues (read on the main thread only).
    struct BlurSnapshot: Equatable {
        var style: PrivacyRedactor.Style
        var regions: [BlurRegion]

        /// Pixel rects for a full-display image — a chat-screen screenshot or
        /// a recording (its frames cover the whole display).
        func pixelRegions(forFullScreen size: CGSize) -> [CGRect] {
            guard size.width > 1, size.height > 1 else { return [] }
            return regions.map {
                CGRect(x: $0.x * size.width, y: $0.y * size.height,
                       width: $0.w * size.width, height: $0.h * size.height)
            }
        }

        /// Pixel rects for a window-mode screenshot: display-space regions
        /// intersected with the window bounds and mapped into the window
        /// image (independent of the backing scale).
        func pixelRegions(forWindow windowBounds: CGRect,
                          displayBounds: CGRect,
                          imageSize: CGSize) -> [CGRect] {
            guard !windowBounds.isEmpty, !displayBounds.isEmpty,
                  imageSize.width > 1, imageSize.height > 1 else { return [] }
            var rects: [CGRect] = []
            for region in regions {
                let displayRect = CGRect(x: displayBounds.minX + region.x * displayBounds.width,
                                         y: displayBounds.minY + region.y * displayBounds.height,
                                         width: region.w * displayBounds.width,
                                         height: region.h * displayBounds.height)
                let overlap = displayRect.intersection(windowBounds)
                guard !overlap.isNull, overlap.width > 1, overlap.height > 1 else { continue }
                rects.append(CGRect(x: (overlap.minX - windowBounds.minX) / windowBounds.width * imageSize.width,
                                    y: (overlap.minY - windowBounds.minY) / windowBounds.height * imageSize.height,
                                    width: overlap.width / windowBounds.width * imageSize.width,
                                    height: overlap.height / windowBounds.height * imageSize.height))
            }
            return rects
        }

        /// Normalized rects for the video pipeline (mapped to frame pixels
        /// per frame inside the composition handler).
        var normalizedRegions: [CGRect] {
            regions.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        }
    }

    @Published private(set) var blurEnabled = false
    @Published private(set) var blurStyle: PrivacyRedactor.Style = .blur
    @Published private(set) var blurRegions: [BlurRegion] = []
    @Published private(set) var voiceOverEnabled = false

    private var fileURL: URL { URL(fileURLWithPath: CaptureOptionsPaths.settingsPath) }

    private init() {
        load()
    }

    // MARK: Persistence

    private struct Payload: Codable {
        var blurEnabled = false
        var blurStyle = PrivacyRedactor.Style.blur.rawValue
        var blurRegions: [BlurRegion] = []
        var voiceOverEnabled = false
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        blurEnabled = payload.blurEnabled
        blurStyle = PrivacyRedactor.Style(rawValue: payload.blurStyle) ?? .blur
        blurRegions = payload.blurRegions
        voiceOverEnabled = payload.voiceOverEnabled
    }

    private func save() {
        let payload = Payload(blurEnabled: blurEnabled,
                              blurStyle: blurStyle.rawValue,
                              blurRegions: blurRegions,
                              voiceOverEnabled: voiceOverEnabled)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Mutations (each persists immediately — ThermalMonitor toggle pattern)

    func setBlurEnabled(_ on: Bool) {
        guard blurEnabled != on else { return }
        blurEnabled = on
        save()
    }

    func setBlurStyle(_ style: PrivacyRedactor.Style) {
        guard blurStyle != style else { return }
        blurStyle = style
        save()
    }

    func setVoiceOverEnabled(_ on: Bool) {
        guard voiceOverEnabled != on else { return }
        voiceOverEnabled = on
        save()
    }

    func setBlurRegions(_ regions: [BlurRegion]) {
        guard blurRegions != regions else { return }
        blurRegions = regions
        save()
    }

    /// Value snapshot for the recorder's background work. Nil when blur is
    /// off or has no areas yet (captures pass through untouched).
    func blurSnapshot() -> BlurSnapshot? {
        guard blurEnabled, !blurRegions.isEmpty else { return nil }
        return BlurSnapshot(style: blurStyle, regions: blurRegions)
    }
}
