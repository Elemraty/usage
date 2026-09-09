import Cocoa

/// Renders the dropdown's rows to a PNG so the layout can be checked without opening the
/// menu by hand. Run: `UsageOverlay --render-preview /tmp/menu.png`
enum MenuPreview {
    static func render(to path: String) {
        let light = column(appearance: NSAppearance(named: .aqua)!)
        let dark = column(appearance: NSAppearance(named: .darkAqua)!)

        let gap: CGFloat = 20
        let size = NSSize(width: light.frame.width + dark.frame.width + gap * 3,
                          height: max(light.frame.height, dark.frame.height) + gap * 2)

        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.gray.setFill()
        NSRect(origin: .zero, size: size).fill()
        draw(light, at: NSPoint(x: gap, y: gap), in: size)
        draw(dark, at: NSPoint(x: gap * 2 + light.frame.width, y: gap), in: size)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func draw(_ view: NSView, at origin: NSPoint, in canvas: NSSize) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // AppKit's image origin is bottom-left; flip so the column reads top-down.
        rep.draw(in: NSRect(x: origin.x, y: canvas.height - origin.y - view.frame.height,
                            width: view.frame.width, height: view.frame.height))
    }

    private static func column(appearance: NSAppearance) -> NSView {
        let rows: [NSView] = [
            ProviderHeaderView(title: "Claude"),
            UsageRowView(label: "5시간", remaining: 77, resetText: "오후 4:00 리셋"),
            UsageRowView(label: "주간", remaining: 81, resetText: "9월 7일 오후 1:00 리셋"),
            ProviderHeaderView(title: "ChatGPT"),
            UsageRowView(label: "5시간", remaining: 52, resetText: "오후 1:40 리셋"),
            UsageRowView(label: "주간", remaining: 63, resetText: "9월 7일 오후 12:31 리셋"),
            ProviderHeaderView(title: "낮은 잔여량 예시"),
            UsageRowView(label: "5시간", remaining: 31, resetText: "오후 6:10 리셋"),
            UsageRowView(label: "주간", remaining: 8, resetText: "9월 8일 오전 9:00 리셋"),
            MessageRowView(text: "로그인이 필요합니다 (sessionKey 없음)",
                            symbolName: "exclamationmark.triangle.fill", color: .systemOrange),
            MessageRowView(text: "3분 전 업데이트", symbolName: nil, color: .tertiaryLabelColor)
        ]

        let height = rows.reduce(0) { $0 + $1.frame.height }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuTheme.rowWidth, height: height))
        container.appearance = appearance
        container.wantsLayer = true
        container.layer?.backgroundColor = appearance.name == .darkAqua
            ? NSColor(white: 0.13, alpha: 1).cgColor
            : NSColor(white: 0.96, alpha: 1).cgColor

        var y: CGFloat = 0
        for row in rows {
            row.appearance = appearance
            row.setFrameOrigin(NSPoint(x: 0, y: height - y - row.frame.height))
            container.addSubview(row)
            y += row.frame.height
        }
        return container
    }
}
