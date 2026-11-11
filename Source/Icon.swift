import AppKit

/// The Nib mark: the tip of a fountain pen. One drawing serves the app icon, the menu bar
/// and the browser extension, so all three always match.
enum NibIcon {
    /// Draws the mark into `rect`. The slit and the hole take the colour `cut`.
    /// Without `cut` they are punched out, which a menu bar template image needs.
    static func draw(in rect: CGRect, color: NSColor, cut: NSColor? = nil) {
        let u = min(rect.width, rect.height) / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }

        let body = NSBezierPath()
        body.move(to: point(50, 8))
        body.curve(to: point(26, 54), controlPoint1: point(45, 24), controlPoint2: point(26, 40))
        body.line(to: point(36, 80))
        body.line(to: point(64, 80))
        body.line(to: point(74, 54))
        body.curve(to: point(50, 8), controlPoint1: point(74, 40), controlPoint2: point(55, 24))
        body.close()
        body.append(NSBezierPath(roundedRect: CGRect(origin: point(36, 85), size: CGSize(width: 28 * u, height: 8 * u)),
                                 xRadius: 2 * u, yRadius: 2 * u))
        color.setFill()
        body.fill()

        // A slit thinner than one pixel disappears in the 16 pixel icon.
        let slit = max(4 * u, 1)
        let details = NSBezierPath(rect: CGRect(x: rect.minX + 50 * u - slit / 2, y: rect.minY + 8 * u, width: slit, height: 44 * u))
        details.appendOval(in: CGRect(origin: point(43.5, 45.5), size: CGSize(width: 13 * u, height: 13 * u)))
        NSGraphicsContext.saveGraphicsState()
        if let cut {
            cut.setFill()
        } else {
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
        }
        details.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The menu bar picture. macOS colours a template image to fit a light or dark menu bar.
    static func menuBar(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nib"
        return image
    }

    /// A green tile with the white mark, as PNG data. `inset` leaves the margin that macOS app icons have.
    static func tile(pixels: Int, inset: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let dark = NSColor(srgbRed: 0.09, green: 0.27, blue: 0.21, alpha: 1)
        let light = NSColor(srgbRed: 0.18, green: 0.45, blue: 0.35, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let side = CGFloat(pixels)
        let square = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * inset, dy: side * inset)
        let shape = NSBezierPath(roundedRect: square, xRadius: square.width * 0.225, yRadius: square.width * 0.225)
        NSGradient(starting: dark, ending: light)?.draw(in: shape, angle: 90)
        draw(in: square.insetBy(dx: square.width * 0.14, dy: square.width * 0.14), color: .white, cut: dark)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The size of the disk image window, in points. `Source/make-dmg.sh` sets the same size and places the two icons.
    static let diskImageSize = CGSize(width: 600, height: 520)

    /// The picture behind the two icons in the disk image window, at two pixels per point.
    /// The app icon sits at the left and the Applications folder at the right. Below them are the steps
    /// for the first launch, which macOS blocks for an app that is not notarized.

    static func diskImageBackground() -> Data? {
        let size = diskImageSize
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Two pixels per point, so the picture is sharp on a Retina display.
        let double = NSAffineTransform()
        double.scale(by: 2)
        double.concat()
        let green = NSColor(srgbRed: 0.13, green: 0.35, blue: 0.27, alpha: 1)
        let ink = NSColor(white: 0.2, alpha: 1), soft = NSColor(white: 0.38, alpha: 1)
        NSGradient(starting: NSColor(srgbRed: 0.93, green: 0.96, blue: 0.93, alpha: 1), ending: .white)?
            .draw(in: CGRect(origin: .zero, size: size), angle: 90)
        // `top` counts from the top edge of the window, as in the layout of the script.
        func text(_ string: String, size font: CGFloat, weight: NSFont.Weight = .regular, color: NSColor,
                  x: CGFloat? = nil, top: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.alignment = x == nil ? .center : .left
            NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: font, weight: weight),
                                                            .foregroundColor: color, .paragraphStyle: style])
                .draw(in: CGRect(x: x ?? 0, y: size.height - top - font * 1.4, width: size.width - (x ?? 0), height: font * 1.4))
        }
        text("Install Nib", size: 26, weight: .bold, color: green, top: 20)
        text("1   Drag Nib to the Applications folder", size: 14, weight: .semibold, color: ink, top: 66)

        // The arrow between the two icons. The script puts their centres 190 points below the top.
        let middle = size.height - 190
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: 250, y: middle))
        arrow.line(to: CGPoint(x: 340, y: middle))
        arrow.lineWidth = 5
        arrow.lineCapStyle = .round
        green.withAlphaComponent(0.7).setStroke()
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: CGPoint(x: 328, y: middle + 14))
        head.line(to: CGPoint(x: 346, y: middle))
        head.line(to: CGPoint(x: 328, y: middle - 14))
        head.lineWidth = 5
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()

        // macOS blocks an app that Apple has not checked, and its message does not say how to go on.
        // So the next steps stand here, where the user looks while the app is copied.
        let card = CGRect(x: 44, y: size.height - 492, width: size.width - 88, height: 196)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
        green.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        edge.lineWidth = 1
        edge.stroke()
        text("2   Open Nib from Applications", size: 14, weight: .semibold, color: ink, x: 64, top: 310)
        text("macOS says “Nib” Not Opened, because Apple has not checked this app.", size: 12, color: soft, x: 88, top: 333)
        text("Click Done. Do not move Nib to the Bin or Trash.", size: 12, color: soft, x: 88, top: 351)
        text("3   Allow Nib one time", size: 14, weight: .semibold, color: ink, x: 64, top: 384)
        // The script puts a link file at the right of this card. A double-click on it opens that page of
        // System Settings, because text in a background picture cannot be clicked.
        text("Double-click the Privacy & Security icon here.", size: 12, color: soft, x: 88, top: 407)
        text("Scroll down and click Open Anyway next to “Nib”.", size: 12, color: soft, x: 88, top: 425)
        text("Then open Nib again. A short guide helps with the setup.", size: 12, color: green, x: 88, top: 456)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes the extension icons and the `AppIcon.iconset` folder. `Source/make-icons.sh` calls this.
    static func write(to folder: String) throws {
        let root = URL(fileURLWithPath: folder)
        let set = root.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for pixels in [16, 32, 48, 128] {
            try tile(pixels: pixels, inset: 0)?.write(to: root.appendingPathComponent("nib-\(pixels).png"))
        }
        for points in [16, 32, 128, 256, 512] {
            try tile(pixels: points, inset: 0.1)?.write(to: set.appendingPathComponent("icon_\(points)x\(points).png"))
            try tile(pixels: points * 2, inset: 0.1)?.write(to: set.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        try diskImageBackground()?.write(to: root.appendingPathComponent("dmg-background.png"))
        // The menu bar mark on white and on black, to check it by eye.
        for (name, back, front) in [("menubar-light", NSColor.white, NSColor.black), ("menubar-dark", NSColor.black, NSColor.white)] {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            back.setFill()
            CGRect(x: 0, y: 0, width: 72, height: 72).fill()
            draw(in: CGRect(x: 18, y: 18, width: 36, height: 36), color: front, cut: back)
            NSGraphicsContext.restoreGraphicsState()
            try rep.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent(name + ".png"))
        }
    }
}
