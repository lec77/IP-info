import AppKit

enum SpinnerFactory {
    /// A small indeterminate spinner that hides itself when stopped.
    static func make() -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.sizeToFit()
        return spinner
    }
}

/// A disabled-looking menu row with a spinner where the check mark would be:
/// "◌ Checking…" — the same layout the Wi-Fi menu uses while scanning.
final class SpinnerMenuItemView: NSView {
    private let spinner = SpinnerFactory.make()
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        autoresizingMask = [.width]
        label.stringValue = title
        label.font = .menuFont(ofSize: 0)
        label.textColor = .disabledControlTextColor
        for view in [spinner, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        spinner.startAnimation(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
