import SwiftUI
import AppKit

/// Draws privacy-blur areas on an in-memory reference screenshot of the chat
/// screen (the image never touches disk). Drag to draw a box, ✕ to remove
/// one. Areas are stored normalized (0…1) so they survive resolution changes.
struct PrivacyAreaEditorSheet: View {
    let reference: NSImage
    let existingRegions: [CaptureOptionsStore.BlurRegion]
    let style: PrivacyRedactor.Style
    let onSave: ([CaptureOptionsStore.BlurRegion]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var regions: [CaptureOptionsStore.BlurRegion] = []
    @State private var dragRect: CGRect?
    @State private var previewImage: NSImage?
    @State private var showPreview = false

    /// Fixed canvas width; height follows the reference's aspect ratio so
    /// drag coordinates map 1:1 onto the normalized image space.
    private let canvasWidth: CGFloat = 356
    private var canvasSize: CGSize {
        let aspect = reference.size.height / max(reference.size.width, 1)
        return CGSize(width: canvasWidth, height: canvasWidth * aspect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blur areas")
                .font(.system(size: 12, weight: .semibold))
            Text("Drag over the screenshot to draw a box covering anything sensitive. Boxes are redacted from every screenshot and recording of this screen — they stay fixed on the screen, so if you move a window, drag its box along too.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            canvas

            HStack(spacing: 10) {
                Toggle("Preview redaction", isOn: $showPreview)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10, weight: .medium))
                Text(regions.isEmpty ? "No areas yet" : "\(regions.count) area\(regions.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !regions.isEmpty {
                    Button {
                        regions = []
                    } label: {
                        Text("Clear all")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(regions.isEmpty ? "Save" : "Save \(regions.count) area\(regions.count == 1 ? "" : "s")") {
                    onSave(regions)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 400)
        .onAppear {
            regions = existingRegions
        }
        .onChange(of: showPreview) { _ in
            renderPreview()
        }
        .onChange(of: regions) { _ in
            // Regions changed — drop the stale preview render.
            previewImage = nil
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            Image(nsImage: showPreview ? (previewImage ?? reference) : reference)
                .resizable()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
            if !showPreview {
                ForEach(regions) { region in
                    regionBox(region)
                }
                if let dragRect {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.red, lineWidth: 1.5)
                        .background(Color.red.opacity(0.15))
                        .frame(width: dragRect.width * canvasSize.width,
                               height: dragRect.height * canvasSize.height)
                        .position(x: dragRect.midX * canvasSize.width,
                                  y: dragRect.midY * canvasSize.height)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    dragRect = normalizedRect(from: value.startLocation, to: value.location)
                }
                .onEnded { value in
                    let rect = normalizedRect(from: value.startLocation, to: value.location)
                    dragRect = nil
                    // Ignore taps / accidental slips — a real area is at least
                    // ~1.2% of the screen in each dimension.
                    guard rect.width > 0.012, rect.height > 0.012 else { return }
                    regions.append(CaptureOptionsStore.BlurRegion(x: rect.minX,
                                                                   y: rect.minY,
                                                                   w: rect.width,
                                                                   h: rect.height))
                }
        )
    }

    private func regionBox(_ region: CaptureOptionsStore.BlurRegion) -> some View {
        let width = max(region.w * canvasSize.width, 18)
        let height = max(region.h * canvasSize.height, 18)
        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.red, lineWidth: 1.5)
                .background(Color.red.opacity(0.22))
            Button {
                regions.removeAll { $0.id == region.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 13, height: 13)
            .background(Circle().fill(Color.red))
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            .position(x: width - 8, y: 8)
            .help("Remove this area")
        }
        .frame(width: width, height: height)
        .position(x: region.x * canvasSize.width + width / 2,
                  y: region.y * canvasSize.height + height / 2)
    }

    // MARK: Helpers

    /// Normalized (0…1) rect between two canvas points, clamped to the canvas.
    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x1 = min(max(start.x, 0), canvasSize.width)
        let y1 = min(max(start.y, 0), canvasSize.height)
        let x2 = min(max(end.x, 0), canvasSize.width)
        let y2 = min(max(end.y, 0), canvasSize.height)
        return CGRect(x: min(x1, x2) / canvasSize.width,
                      y: min(y1, y2) / canvasSize.height,
                      width: abs(x2 - x1) / canvasSize.width,
                      height: abs(y2 - y1) / canvasSize.height)
    }

    /// Renders the actual redaction over the reference image for the preview
    /// toggle, so the user can confirm the boxes cover what they think.
    private func renderPreview() {
        guard showPreview, previewImage == nil else { return }
        guard let cg = reference.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let pixelRegions = regions.map {
            CGRect(x: $0.x * CGFloat(cg.width), y: $0.y * CGFloat(cg.height),
                   width: $0.w * CGFloat(cg.width), height: $0.h * CGFloat(cg.height))
        }
        guard let out = PrivacyRedactor.redact(cg, regions: pixelRegions, style: style) else { return }
        previewImage = NSImage(cgImage: out, size: reference.size)
    }
}
