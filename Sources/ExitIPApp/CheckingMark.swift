import AppKit

/// The in-progress mark for a native menu row: a template SF Symbol
/// (`arrow.triangle.2.circlepath`, the system's "refreshing" glyph) rendered
/// as a ring of rotated frames and cycled onto `NSMenuItem.image`. The row
/// stays a plain NSMenuItem, so AppKit does the layout and tints the
/// template image like the row's text (grey when the item is disabled).
@MainActor
final class CheckingMark {
    private static let frameCount = 24
    private static let frames: [NSImage] = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Checking")?
            .withSymbolConfiguration(config) else { return [] }
        let side = ceil(max(symbol.size.width, symbol.size.height))
        let size = NSSize(width: side, height: side)
        return (0..<frameCount).map { index in
            let angle = -CGFloat(index) / CGFloat(frameCount) * 2 * .pi // clockwise
            let frame = NSImage(size: size, flipped: false) { rect in
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                transform.rotate(byRadians: angle)
                transform.translateX(by: -rect.midX, yBy: -rect.midY)
                transform.concat()
                symbol.draw(in: NSRect(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2,
                                       width: symbol.size.width, height: symbol.size.height))
                return true
            }
            frame.isTemplate = true
            return frame
        }
    }()

    private weak var item: NSMenuItem?
    private var timer: Timer?
    private var index = 0

    /// Animates `item.image` until `stop()`; one full turn per ~1 s.
    func start(on item: NSMenuItem) {
        stop()
        self.item = item
        index = 0
        item.image = Self.frames.first
        let timer = Timer(timeInterval: 1.0 / Double(Self.frameCount), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        // .common covers menu tracking, so it keeps turning while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        item?.image = nil
        item = nil
    }

    private func advance() {
        guard let item, !Self.frames.isEmpty else { return }
        index = (index + 1) % Self.frames.count
        item.image = Self.frames[index]
    }
}
