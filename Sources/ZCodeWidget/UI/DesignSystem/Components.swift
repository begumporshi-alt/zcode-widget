import SwiftUI
import AppKit

// MARK: - DesignCard

/// The card container pattern (controlBackground + continuous 8pt corner)
/// that was previously duplicated inline across Tokens/Providers/Captures views.
struct DesignCard<Content: View>: View {
    var padding: CGFloat = ZTheme.paddingCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ZTheme.radius, style: .continuous)
                    .fill(ZTheme.card)
            )
    }
}

// MARK: - Button styles

/// Filled accent button for the primary action in a view.
struct ZPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZTheme.bodySemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ZTheme.radius, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

/// Bordered "quiet" button for secondary actions.
struct ZGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZTheme.bodyMedium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ZTheme.radius, style: .continuous)
                    .fill(configuration.isPressed ? ZTheme.highlight : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ZTheme.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2))
            )
    }
}

// MARK: - FilterChip

/// Horizontal filter chip — extracted from the Prompts library pattern.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ZTheme.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? ZTheme.highlightStrong : Color.clear)
                .cornerRadius(ZTheme.radius)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SectionHeader

/// Small tracked-caps caption used above content sections.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - SwatchDot

/// A palette color rendered from its hex string; clicking copies the hex.
struct SwatchDot: View {
    let swatch: DesignSwatch
    var size: CGFloat = 16
    var showsName = false
    let onCopy: (String) -> Void

    var body: some View {
        Button {
            onCopy(swatch.hex)
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(Color(hex: swatch.hex) ?? Color(nsColor: .lightGray))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(ZTheme.hairline))
                Text(showsName ? swatch.hex : swatch.name)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help("Copy \(swatch.hex)")
    }
}

// MARK: - Clipboard helper

/// Shared pasteboard write used by every copy action.
@discardableResult
func copyToPasteboard(_ text: String) -> Bool {
    let pb = NSPasteboard.general
    pb.clearContents()
    return pb.setString(text, forType: .string)
}
