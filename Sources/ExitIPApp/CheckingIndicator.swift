import AppKit

/// A template SF Symbol that rotates continuously — the app's "in progress"
/// mark. It's drawn as a glyph of the same family as the title's prefix
/// glyphs (⛔ ⚠︎ ⏸): monochrome, text-sized, tinted for wherever it sits
/// (the menu bar's vibrant text, a disabled menu row's grey), so it reads as
/// part of the text rather than as a control dropped next to it.
final class RotatingSymbolView: NSView {
    private let symbolLayer = CALayer()
    private let image: NSImage
    private let color: NSColor
    private static let animationKey = "spin"

    /// `arrow.triangle.2.circlepath` is the system's "refreshing" symbol.
    init(symbolName: String = "arrow.triangle.2.circlepath", pointSize: CGFloat, color: NSColor) {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Checking")
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        self.image = base?.withSymbolConfiguration(config) ?? NSImage()
        self.color = color
        let side = ceil(max(image.size.width, image.size.height))
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        symbolLayer.contentsGravity = .resizeAspect
        symbolLayer.frame = bounds // a standalone layer rotates about its centre
        layer?.addSublayer(symbolLayer)
        retint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isAnimating = false {
        didSet {
            guard isAnimating != oldValue else { return }
            isHidden = !isAnimating
            isAnimating ? startSpinning() : symbolLayer.removeAnimation(forKey: Self.animationKey)
        }
    }

    override func layout() {
        super.layout()
        symbolLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        retint()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        symbolLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        symbolLayer.contentsScale = window?.backingScaleFactor ?? 2
        retint() // the appearance (menu bar vs. menu) is only known once hosted
        // Core Animation drops animations from layers that left the screen.
        if isAnimating, symbolLayer.animation(forKey: Self.animationKey) == nil { startSpinning() }
    }

    /// Template symbols don't tint inside a bare CALayer, so the glyph is
    /// rendered in the colour resolved for the current appearance. The colour
    /// is resolved *now*, under this view's effective appearance (the menu
    /// bar's, or the menu's): an image drawing handler runs later, when Core
    /// Animation renders it, under whatever appearance is current then.
    private func retint() {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        let fixed = NSColor(cgColor: resolved) ?? color
        let tinted = NSImage(size: image.size, flipped: false) { [image] rect in
            image.draw(in: rect)
            fixed.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        symbolLayer.contents = tinted
    }

    private func startSpinning() {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi // clockwise
        spin.duration = 1.1
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        symbolLayer.add(spin, forKey: Self.animationKey)
    }
}

/// Where AppKit puts things in a standard menu row, measured off an
/// `NSMenuItemCell` so custom rows line up with native ones exactly.
enum MenuRowMetrics {
    static var rowHeight: CGFloat { probe.height }
    /// x where the title text starts.
    static var titleX: CGFloat { probe.titleX }
    /// x of the middle of the check-mark column.
    static var stateCenterX: CGFloat { probe.stateCenterX }
    /// Space kept clear at the trailing edge (where "⌘R" would sit).
    static let trailing: CGFloat = 12

    static let font = NSFont.menuFont(ofSize: 0)

    private static let probe: (height: CGFloat, titleX: CGFloat, stateCenterX: CGFloat) = {
        let item = NSMenuItem(title: "Probe", action: nil, keyEquivalent: "")
        item.state = .on
        let cell = NSMenuItemCell()
        cell.menuItem = item
        cell.font = font
        let height = cell.cellSize.height
        let bounds = NSRect(x: 0, y: 0, width: 300, height: height)
        return (height, cell.titleRect(forBounds: bounds).minX, cell.stateImageRect(forBounds: bounds).midX)
    }()
}

/// The "Last checked" row while a check is running: the rotating mark in the
/// check-mark column, then the usual greyed "Label: value" text.
final class CheckingMenuItemView: NSView {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: MenuRowMetrics.rowHeight))
        autoresizingMask = [.width]
        let mark = RotatingSymbolView(pointSize: 11, color: .disabledControlTextColor)
        let label = NSTextField(labelWithString: title)
        label.font = MenuRowMetrics.font
        label.textColor = .disabledControlTextColor
        for view in [mark, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetrics.stateCenterX),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: mark.frame.width),
            mark.heightAnchor.constraint(equalToConstant: mark.frame.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetrics.titleX),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuRowMetrics.trailing),
        ])
        mark.isAnimating = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
