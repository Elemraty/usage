import Cocoa

/// Shared metrics and colors for the dropdown's custom-drawn rows.
///
/// The menu used to be plain (disabled) NSMenuItem text with "█░" characters standing in
/// for a gauge, which rendered as a washed-out grey smear. These views draw real capsule
/// bars instead, tinted by how much of the limit is left.
enum MenuTheme {
    static let rowWidth: CGFloat = 300
    static let inset: CGFloat = 14
    static let labelWidth: CGFloat = 44
    static let labelGap: CGFloat = 10
    static let percentWidth: CGFloat = 46
    static let barHeight: CGFloat = 7

    static var barX: CGFloat { inset + labelWidth + labelGap }
    static var barWidth: CGFloat { rowWidth - inset - percentWidth - 8 - barX }

    /// Green when there's plenty left, amber when it's getting tight, red when nearly gone.
    static func levelColor(remaining: Int) -> NSColor {
        switch remaining {
        case ..<15: return .systemRed
        case ..<40: return .systemOrange
        default: return .systemGreen
        }
    }
}

/// "Claude" / "ChatGPT" section heading.
final class ProviderHeaderView: NSView {
    private let title: String

    init(title: String) {
        self.title = title
        // Extra headroom separates one provider's block from the previous one's reset line.
        super.init(frame: NSRect(x: 0, y: 0, width: MenuTheme.rowWidth, height: 32))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        title.draw(at: NSPoint(x: MenuTheme.inset, y: 13), withAttributes: attrs)
    }
}

/// One limit window: label, capsule gauge, remaining %, and the reset time underneath.
final class UsageRowView: NSView {
    private let label: String
    private let remaining: Int?
    private let resetText: String?

    init(label: String, remaining: Int?, resetText: String?) {
        self.label = label
        self.remaining = remaining
        self.resetText = resetText
        let height: CGFloat = resetText == nil ? 26 : 38
        super.init(frame: NSRect(x: 0, y: 0, width: MenuTheme.rowWidth, height: height))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        label.draw(at: NSPoint(x: MenuTheme.inset, y: 3), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])

        let barY: CGFloat = 6
        let radius = MenuTheme.barHeight / 2
        let track = NSRect(x: MenuTheme.barX, y: barY, width: MenuTheme.barWidth, height: MenuTheme.barHeight)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        if let remaining = remaining {
            let clamped = CGFloat(min(100, max(0, remaining)))
            // Keep a minimum width so a nearly-empty bar still reads as a capsule, not a dot.
            let width = max(MenuTheme.barHeight, MenuTheme.barWidth * clamped / 100)
            MenuTheme.levelColor(remaining: remaining).setFill()
            NSBezierPath(roundedRect: NSRect(x: MenuTheme.barX, y: barY, width: width, height: MenuTheme.barHeight),
                          xRadius: radius, yRadius: radius).fill()
        }

        let percentText = remaining.map { "\($0)%" } ?? "—"
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let percentSize = percentText.size(withAttributes: percentAttrs)
        percentText.draw(at: NSPoint(x: MenuTheme.rowWidth - MenuTheme.inset - percentSize.width, y: 2),
                          withAttributes: percentAttrs)

        if let resetText = resetText {
            resetText.draw(at: NSPoint(x: MenuTheme.barX, y: 20), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
        }
    }
}

/// Wrapped status / error text. Long API errors used to stretch the menu off-screen;
/// this keeps them inside the menu width and clips them to a couple of lines.
final class MessageRowView: NSView {
    private let text: String
    private let symbolName: String?
    private let color: NSColor
    private let textRect: NSRect

    init(text: String, symbolName: String? = nil, color: NSColor = .secondaryLabelColor) {
        let trimmed = text.count > 180 ? String(text.prefix(180)) + "…" : text
        self.text = trimmed
        self.symbolName = symbolName
        self.color = color

        let textX = MenuTheme.inset + (symbolName == nil ? 0 : 20)
        let available = MenuTheme.rowWidth - textX - MenuTheme.inset
        let height = MessageRowView.height(for: trimmed, width: available)
        self.textRect = NSRect(x: textX, y: 4, width: available, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuTheme.rowWidth, height: height + 10))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    override var isFlipped: Bool { true }

    private static func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func height(for text: String, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 40),
            options: [.usesLineFragmentOrigin],
            attributes: attributes(.labelColor)
        )
        return min(40, max(14, ceil(bounding.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let symbolName = symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            // Tint via a palette configuration. Drawing the template and then filling the
            // rect with .sourceAtop paints the whole box instead of just the glyph, because
            // the destination (the menu background) is already opaque.
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let tinted = image.withSymbolConfiguration(config) ?? image
            // respectFlipped is required: this view is flipped, and without it the glyph
            // draws upside down.
            tinted.draw(in: NSRect(x: MenuTheme.inset, y: 3, width: 14, height: 14),
                         from: .zero, operation: .sourceOver, fraction: 1.0,
                         respectFlipped: true, hints: nil)
        }
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin],
                                 attributes: MessageRowView.attributes(color))
    }
}
