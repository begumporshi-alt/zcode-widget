import SwiftUI

// MARK: - Theme (design tokens)

/// Shared design tokens for ZCode Widget views.
/// New views (Design Library onward) build on these; older views still use
/// inline styling and can migrate to `ZTheme` incrementally.
enum ZTheme {
    // MARK: Colors

    /// Card/inset surfaces — the `controlBackgroundColor` pattern used app-wide.
    static let card = Color(nsColor: .controlBackgroundColor)
    /// Subtle divider strokes.
    static let hairline = Color.primary.opacity(0.12)
    /// Accent wash used for selection/hover states (matches existing views).
    static let highlight = Color.accentColor.opacity(0.15)
    static let highlightStrong = Color.accentColor.opacity(0.2)

    // MARK: Metrics

    static let radiusSmall: CGFloat = 6
    static let radius: CGFloat = 8
    static let radiusLarge: CGFloat = 12
    static let paddingCard: CGFloat = 10

    // MARK: Fonts (the app's existing type scale, named)

    /// 8pt bold — badge text.
    static let badge = Font.system(size: 8, weight: .bold)
    /// 10pt regular — fine print, hex codes.
    static let micro = Font.system(size: 10)
    /// 11pt medium — chips, labels.
    static let label = Font.system(size: 11, weight: .medium)
    /// 11pt semibold — section captions.
    static let caption = Font.system(size: 11, weight: .semibold)
    /// 12pt regular — body text.
    static let body = Font.system(size: 12)
    /// 12pt medium.
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    /// 12pt semibold — row titles, buttons.
    static let bodySemibold = Font.system(size: 12, weight: .semibold)
    /// 14pt semibold — sheet titles.
    static let title = Font.system(size: 14, weight: .semibold)
    /// 16pt bold monospaced — stat values.
    static let statValue = Font.system(size: 16, weight: .bold, design: .monospaced)
}

// MARK: - Hex colors

extension Color {
    /// Parses `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`, and 3-digit shorthand.
    /// Returns nil (instead of crashing) on anything unparsable so stored
    /// user-entered hex strings render as a neutral gray instead.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }
        let r, g, b, a: Double
        if value.count == 8 {
            r = Double((number >> 24) & 0xFF) / 255
            g = Double((number >> 16) & 0xFF) / 255
            b = Double((number >> 8) & 0xFF) / 255
            a = Double(number & 0xFF) / 255
        } else {
            r = Double((number >> 16) & 0xFF) / 255
            g = Double((number >> 8) & 0xFF) / 255
            b = Double(number & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
