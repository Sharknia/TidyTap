import AppKit

/// The single-window settings surface. Persistence and helper coordination are
/// provided by a coordinator through the delegate or closure hooks.
final class SettingsViewController: NSViewController {
    weak var delegate: SettingsViewControllerDelegate?
    var onSettingsChange: ((TidyTapSettings) -> Void)?
    var onPermissionSettingsRequest: (() -> Void)?
    private(set) var settings: TidyTapSettings
    private let stack = NSStackView()
    private let permissionContainer = NSStackView()
    private let permissionMessage = NSTextField(wrappingLabelWithString: "")
    private let statusMessage = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: TidyTapStrings.openSystemSettings, target: nil, action: nil)
    private var requestedPermission: TidyTapPermission?
    private let capsButton = NSButton(checkboxWithTitle: TidyTapStrings.capsLockInputSourceSwitching, target: nil, action: nil)
    private let wheelButton = NSButton(checkboxWithTitle: TidyTapStrings.reverseMouseWheelVertically, target: nil, action: nil)
    private let sideButton = NSButton(checkboxWithTitle: TidyTapStrings.sideButtonNavigation, target: nil, action: nil)
    private let loginButton = NSButton(checkboxWithTitle: TidyTapStrings.launchAtLogin, target: nil, action: nil)

    init(settings: TidyTapSettings = .defaults, delegate: SettingsViewControllerDelegate? = nil) {
        self.settings = settings
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false; view = root
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        let title = NSTextField(labelWithString: TidyTapStrings.appName); title.font = .systemFont(ofSize: 24, weight: .semibold); stack.addArrangedSubview(title); stack.setCustomSpacing(4, after: title)
        addSection([capsButton, wheelButton, sideButton], title: nil)
        addDivider()
        addSection([loginButton], title: TidyTapStrings.options)
        statusMessage.textColor = .secondaryLabelColor; statusMessage.maximumNumberOfLines = 2; stack.addArrangedSubview(statusMessage)
        permissionContainer.orientation = .vertical; permissionContainer.alignment = .leading; permissionContainer.spacing = 10; permissionContainer.isHidden = true
        permissionMessage.maximumNumberOfLines = 0
        permissionContainer.addArrangedSubview(permissionMessage)
        permissionButton.target = self; permissionButton.action = #selector(openPermissionSettings); permissionButton.bezelStyle = .rounded; permissionContainer.addArrangedSubview(permissionButton); stack.addArrangedSubview(permissionContainer)
        addDivider()
        let footer = NSStackView(); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 5
        footer.addArrangedSubview(NSTextField(labelWithString: versionText())); footer.addArrangedSubview(linkButton(title: TidyTapStrings.email, url: TidyTapStrings.emailURL)); footer.addArrangedSubview(linkButton(title: TidyTapStrings.github, url: TidyTapStrings.githubURL)); stack.addArrangedSubview(footer)
        apply(settings)
    }

    private func addSection(_ buttons: [NSButton], title: String?) {
        let section = NSStackView(); section.orientation = .vertical; section.alignment = .leading; section.spacing = 8
        if let title {
            let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13, weight: .semibold); label.textColor = .secondaryLabelColor; section.addArrangedSubview(label); section.setCustomSpacing(6, after: label)
        }
        buttons.forEach { button in
            button.target = self; button.action = #selector(settingChanged(_:)); button.controlSize = .large; button.setAccessibilityLabel(button.title); section.addArrangedSubview(button)
        }
        stack.addArrangedSubview(section)
    }
    private func addDivider() { let divider = NSBox(); divider.boxType = .separator; stack.addArrangedSubview(divider) }
    func apply(_ settings: TidyTapSettings) {
        self.settings = settings; guard isViewLoaded else { return }
        capsButton.state = settings.capsLockInputSourceSwitching ? .on : .off; wheelButton.state = settings.reverseMouseWheelVertically ? .on : .off; sideButton.state = settings.sideButtonNavigation ? .on : .off; loginButton.state = settings.launchAtLogin ? .on : .off
    }
    func showApplyStatus(_ status: TidyTapApplyStatus, permission: TidyTapPermission? = nil) {
        let isPending = status.outcome == .pending
        [capsButton, wheelButton, sideButton, loginButton].forEach { $0.isEnabled = !isPending }
        switch status.outcome {
        case .pending:
            statusMessage.stringValue = TidyTapStrings.applyingChanges; showPermissionMessage(nil)
        case .applied:
            statusMessage.stringValue = TidyTapStrings.changesApplied; showPermissionMessage(nil)
        case .partiallyApplied:
            statusMessage.stringValue = ""; showPermissionMessage(TidyTapStrings.permissionRequired, permission: permission)
        case .failed:
            let denied = permission != nil
            statusMessage.stringValue = denied ? "" : TidyTapStrings.changesCouldNotBeApplied
            showPermissionMessage(denied ? TidyTapStrings.permissionRequired : nil, permission: permission)
        case .recoveryRequired:
            statusMessage.stringValue = TidyTapStrings.changesCouldNotBeApplied; showPermissionMessage(nil)
        }
    }
    /// Displays the inline permission/error area; pass nil to hide it.
    func showPermissionMessage(_ message: String?, permission: TidyTapPermission? = nil) { requestedPermission = permission; permissionMessage.stringValue = message ?? ""; permissionContainer.isHidden = message == nil }
    private func versionText() -> String { let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"; return String(format: TidyTapStrings.versionFormat, version) }
    private func linkButton(title: String, url: URL) -> NSButton { let button = NSButton(title: title, target: self, action: #selector(openLink(_:))); button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString); button.isBordered = false; button.alignment = .left; button.contentTintColor = .linkColor; return button }

    @objc private func settingChanged(_ sender: NSButton) {
        switch sender { case capsButton: settings.capsLockInputSourceSwitching = sender.state == .on; case wheelButton: settings.reverseMouseWheelVertically = sender.state == .on; case sideButton: settings.sideButtonNavigation = sender.state == .on; case loginButton: settings.launchAtLogin = sender.state == .on; default: return }
        // A coordinator may choose to handle this synchronously. The closure
        // is a fallback hook so actions are never delivered twice.
        if delegate?.settingsViewController(self, didChange: settings) != true {
            onSettingsChange?(settings)
        }
    }
    @objc private func openPermissionSettings() {
        if delegate?.settingsViewControllerRequestsPermissionSettings(self, permission: requestedPermission ?? .accessibility) != true {
            onPermissionSettingsRequest?()
        }
    }
    @objc private func openLink(_ sender: NSButton) { guard let value = sender.identifier?.rawValue, let url = URL(string: value) else { return }; NSWorkspace.shared.open(url) }
}

@MainActor
protocol SettingsViewControllerDelegate: AnyObject {
    /// Return true when the delegate handled the action; false selects the
    /// controller's closure fallback.
    func settingsViewController(_ controller: SettingsViewController, didChange settings: TidyTapSettings) -> Bool
    func settingsViewControllerRequestsPermissionSettings(_ controller: SettingsViewController, permission: TidyTapPermission) -> Bool
}
