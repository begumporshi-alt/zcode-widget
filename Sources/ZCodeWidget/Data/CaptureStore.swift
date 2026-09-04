import AppKit
import AVFoundation
import ImageIO

/// Non-isolated folder path holder: stores live in `~/.zcode/captures/`.
/// The folder itself is created by CaptureStore at launch.
enum CapturePaths {
    /// Overridable for tests (pattern from TaskStore.tasksPath).
    static var folderPath = NSHomeDirectory() + "/.zcode/captures"
}

/// Owns the widget's capture library. The `~/.zcode/captures` folder is the
/// source of truth: the store scans it into items and serves thumbnails and
/// video durations for the Captures tab. Deletes go to the Trash.
@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    enum Kind { case image, video }

    struct CaptureItem: Identifiable, Equatable {
        let url: URL
        let kind: Kind
        let createdAt: Date
        let sizeBytes: Int
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var sizeLabel: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        }
    }

    @Published private(set) var items: [CaptureItem] = []

    private let thumbCache = NSCache<NSURL, NSImage>()
    private let previewCache = NSCache<NSURL, NSImage>()
    private var durations: [URL: TimeInterval] = [:]

    private init() {
        try? FileManager.default.createDirectory(atPath: CapturePaths.folderPath,
                                                 withIntermediateDirectories: true)
        rescan()
    }

    // MARK: Library

    func rescan() {
        let folder = URL(fileURLWithPath: CapturePaths.folderPath, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        var list: [CaptureItem] = []
        for file in files {
            guard let kind = Self.kind(for: file.pathExtension) else { continue }
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
            list.append(CaptureItem(url: file,
                                    kind: kind,
                                    createdAt: values.contentModificationDate ?? .distantPast,
                                    sizeBytes: values.fileSize ?? 0))
        }
        items = list.sorted { $0.createdAt > $1.createdAt }
    }

    private nonisolated static func kind(for ext: String) -> Kind? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic": return .image
        case "mov", "mp4": return .video
        default: return nil
        }
    }

    // MARK: New capture files (called from the recorder's background queue)

    /// Builds a never-colliding capture URL in the captures folder.
    nonisolated static func makeFileURL(kind: Kind) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        let prefix = kind == .image ? "shot" : "rec"
        let ext = kind == .image ? "png" : "mov"
        var url = URL(fileURLWithPath: CapturePaths.folderPath)
            .appendingPathComponent("\(prefix)-\(stamp).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = URL(fileURLWithPath: CapturePaths.folderPath)
                .appendingPathComponent("\(prefix)-\(stamp)-\(n).\(ext)")
            n += 1
        }
        return url
    }

    // MARK: Thumbnails, previews & durations

    func thumbnail(for item: CaptureItem) async -> NSImage? {
        if let cached = thumbCache.object(forKey: item.url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) {
            Self.makeImage(item, maxPixel: 480)
        }.value
        if let image { thumbCache.setObject(image, forKey: item.url as NSURL) }
        return image
    }

    /// Larger render for the detail preview (full-width panel needs ~1600px at 2x).
    func preview(for item: CaptureItem) async -> NSImage? {
        if let cached = previewCache.object(forKey: item.url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) {
            Self.makeImage(item, maxPixel: 1600)
        }.value
        if let image { previewCache.setObject(image, forKey: item.url as NSURL) }
        return image
    }

    private nonisolated static func makeImage(_ item: CaptureItem, maxPixel: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func duration(for item: CaptureItem) async -> TimeInterval? {
        guard item.kind == .video else { return nil }
        if let cached = durations[item.url] { return cached }
        let seconds = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: item.url)
            return try? await asset.load(.duration).seconds
        }.value
        if let seconds, seconds.isFinite { durations[item.url] = seconds }
        return seconds
    }

    nonisolated static func durationLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Actions

    @discardableResult
    func trash(_ item: CaptureItem) -> Bool {
        thumbCache.removeObject(forKey: item.url as NSURL)
        previewCache.removeObject(forKey: item.url as NSURL)
        durations[item.url] = nil
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            rescan()
            return true
        } catch {
            return false
        }
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: CapturePaths.folderPath, isDirectory: true))
    }
}
