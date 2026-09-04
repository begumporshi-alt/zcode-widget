import Foundation
import CoreGraphics
import CoreImage
import AVFoundation

/// Privacy redaction for captured stills and recordings: blur or pixelate
/// user-drawn regions. Pure functions with no app dependencies so the whole
/// pipeline compiles headlessly with `swiftc` for testing.
enum PrivacyRedactor {

    enum Style: String {
        case blur
        case pixelate
    }

    enum RedactorError: LocalizedError {
        case exportSessionUnavailable
        case exportFailed(String?)

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                return "Couldn't create an export session for the recording"
            case .exportFailed(let detail):
                return "Export failed\(detail.map { " — \($0)" } ?? "")"
            }
        }
    }

    /// Shared render context — creating one per frame is expensive.
    /// CIContext is safe to use from multiple threads.
    static let context = CIContext()

    // MARK: Stills

    /// Redacts `regions` (pixel rects, top-left origin) and returns a new
    /// image; nil when rendering fails (caller keeps the original).
    static func redact(_ image: CGImage, regions: [CGRect], style: Style) -> CGImage? {
        guard !regions.isEmpty else { return image }
        let input = CIImage(cgImage: image)
        let output = redactCIImage(input, regions: regions, style: style)
        return context.createCGImage(output, from: input.extent)
    }

    // MARK: CIImage (video frames + editor preview)

    /// `regions` are in the image's PIXEL space with a TOP-LEFT origin; Core
    /// Image uses a bottom-left origin, so rects are flipped internally.
    static func redactCIImage(_ input: CIImage, regions: [CGRect], style: Style) -> CIImage {
        guard !regions.isEmpty else { return input }
        let extent = input.extent
        guard extent.width > 1, extent.height > 1 else { return input }
        let bounds = CGRect(x: 0, y: 0, width: extent.width, height: extent.height)
        var result = input
        for region in regions {
            // Pad outward so no legible sliver survives at the box edges.
            let padded = region.insetBy(dx: -4, dy: -4).intersection(bounds)
            guard padded.width > 2, padded.height > 2 else { continue }
            // Flip the top-left rect into CI coordinates.
            let ciRect = CGRect(x: extent.minX + padded.minX,
                                y: extent.maxY - padded.maxY,
                                width: padded.width,
                                height: padded.height)
            let patch = result.cropped(to: ciRect)
            let filtered: CIImage
            switch style {
            case .blur:
                let radius = max(18, min(padded.width, padded.height) * 0.18)
                filtered = patch
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
                    .cropped(to: ciRect)
            case .pixelate:
                let scale = min(40, max(16, min(padded.width, padded.height) / 8))
                filtered = patch
                    .clampedToExtent()
                    .applyingFilter("CIPixellate",
                                    parameters: ["inputScale": scale,
                                                 "inputCenter": CIVector(x: ciRect.midX, y: ciRect.midY)])
                    .cropped(to: ciRect)
            }
            result = filtered.composited(over: result)
        }
        return result
    }

    // MARK: Video

    /// Re-exports the recording at `sourceURL` with `normalizedRegions`
    /// (0…1 of the frame, top-left origin) redacted; the audio track passes
    /// through untouched. Overwrites `outputURL`. Throws on failure — the
    /// caller owns the fallback (the raw file is left alone).
    static func processVideo(at sourceURL: URL,
                             outputURL: URL,
                             normalizedRegions: [CGRect],
                             style: Style,
                             progress: ((Double) -> Void)? = nil) async throws {
        guard !normalizedRegions.isEmpty else { return }
        let asset = AVURLAsset(url: sourceURL)
        let composition = try await AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let source = request.sourceImage
            let extent = source.extent
            let pixelRegions = normalizedRegions.map {
                CGRect(x: $0.minX * extent.width,
                       y: $0.minY * extent.height,
                       width: $0.width * extent.width,
                       height: $0.height * extent.height)
            }
            request.finish(with: redactCIImage(source, regions: pixelRegions, style: style),
                           context: context)
        })
        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            throw RedactorError.exportSessionUnavailable
        }
        export.videoComposition = composition
        export.outputURL = outputURL
        export.outputFileType = .mov
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let poller = progress.map { report in
            Task {
                while !Task.isCancelled {
                    report(Double(export.progress))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        defer { poller?.cancel() }
        await export.export()
        if export.status != .completed {
            throw RedactorError.exportFailed(export.error?.localizedDescription)
        }
    }
}
