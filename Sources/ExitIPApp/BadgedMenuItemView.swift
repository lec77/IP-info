import AppKit
import ExitIPCore

/// A menu row with the title on the left and a coloured status pill on the
/// right. Setting `NSMenuItem.view` opts out of the standard row, so the
/// highlight and the click are reproduced here.
final class BadgedMenuItemView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let pill = NSView()
    private var tint: NSColor = .systemGray

    // Matches the standard row: text starts past the check-mark column.
    private static let leading: CGFloat = 21
    private static let trailing: CGFloat = 12
    private static let rowHeight: CGFloat = 24

    init(title: String, badge: SignInBadge) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: Self.rowHeight))
        autoresizingMask = [.width]

        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        badgeLabel.alignment = .center
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8

        for view in [titleLabel, pill, badgeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(titleLabel)
        addSubview(pill)
        pill.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leading),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -12),

            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailing),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 16),

            badgeLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            badgeLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            badgeLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        configure(title: title, badge: badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, badge: SignInBadge) {
        titleLabel.stringValue = title
        badgeLabel.stringValue = badge.text
        tint = Self.color(for: badge.tone)
        applyColors()
    }

    private static func color(for tone: SignInBadge.Tone) -> NSColor {
        switch tone {
        case .alert: return .systemOrange
        case .ok: return .systemGreen
        case .neutral: return .systemGray
        }
    }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    private func applyColors() {
        titleLabel.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        badgeLabel.textColor = tint
        pill.layer?.backgroundColor = tint.withAlphaComponent(0.18).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func draw(_ dirtyRect: NSRect) {
        applyColors()
        guard isHighlighted else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5)
        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
