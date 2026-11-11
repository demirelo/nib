import AppKit

extension NSView {
    /// A picture of the view as it draws now. `Nib --render <folder>` uses it to check the layout
    /// of the windows without a screen recording.
    func png(background: NSColor = .windowBackgroundColor) -> Data? {
        layoutSubtreeIfNeeded()
        guard bounds.width > 0, bounds.height > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background.setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// A see-through window that draws an underline under every issue in the focused text field.
/// Clicks pass through it, so the app below works as usual.
@MainActor
final class Overlay {
    private final class Lines: NSView {
        var lines: [(rect: CGRect, color: NSColor)] = [] { didSet { needsDisplay = true } }

        override func draw(_ dirtyRect: NSRect) {
            for line in lines {
                line.color.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: line.rect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private let window: NSPanel
    private let view = Lines()

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
    }

    /// Converts text bounds into underline rectangles inside the window that covers `frame`.
    /// All input uses Accessibility coordinates: the origin is the top left of the main screen.
    static func layout(_ bounds: [CGRect], within frame: CGRect, margin: CGFloat = 4) -> [CGRect] {
        bounds.compactMap { rect in
            // A range that wraps over lines reports one tall box. An underline under it would mislead.
            guard rect.width > 2, rect.height > 4, rect.height < 60, frame.insetBy(dx: -2, dy: -2).contains(rect) else { return nil }
            return CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY + margin - 2, width: rect.width, height: 2)
        }
    }

    /// An error gets an orange line. A style suggestion gets a green one.
    func show(_ marks: [(bounds: CGRect, suggestion: Bool)], within frame: CGRect) {
        let margin: CGFloat = 4
        let lines = marks.flatMap { mark in
            Overlay.layout([mark.bounds], within: frame, margin: margin)
                .map { (rect: $0, color: mark.suggestion ? NSColor.systemGreen : NSColor.systemOrange) }
        }
        guard !lines.isEmpty, let primary = NSScreen.screens.first else {
            hide()
            return
        }
        let origin = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY - margin)
        window.setFrame(CGRect(origin: origin, size: CGSize(width: frame.width, height: frame.height + margin)), display: false)
        view.lines = lines
        window.orderFrontRegardless()
    }

    func hide() {
        if window.isVisible { window.orderOut(nil) }
        view.lines = []
    }
}
