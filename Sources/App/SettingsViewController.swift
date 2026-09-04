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
    private let capsButton = NSButton(checkboxWithTitle: TidyTapStrings.capsLockInputSourceSwitching, target: nil, action: nil)
    private let wheelButton = NSButton(checkboxWithTitle: TidyTapStrings.reverseMouseWheelVertically, target: nil, action: nil)
    private let sideButton = NSButton(checkboxWithTitle: TidyTapStrings.sideButtonNavigation, target: nil, action: nil)
    private let loginButton = NSButton(checkboxWithTitle: TidyTapStrings.launchAtLogin, target: nil, action: nil)
    private let menuBarButton = NSButton(checkboxWithTitle: TidyTapStrings.showInMenuBar, target: nil, action: nil)

    init(settings: TidyTapSettings = .defaults, delegate: SettingsViewControllerDelegate? = nil) {
        self.settings = settings
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false; view = root
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28), stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        let title = NSTextField(labelWithString: TidyTapStrings.appName); title.font = .systemFont(ofSize: 24, weight: .semibold); stack.addArrangedSubview(title); stack.setCustomSpacing(16, after: title)
        [capsButton, wheelButton, sideButton].forEach { addCheckbox($0) }
        let options = NSTextField(labelWithString: TidyTapStrings.options); options.font = .systemFont(ofSize: 13, weight: .semibold); options.textColor = .secondaryLabelColor; stack.addArrangedSubview(options); stack.setCustomSpacing(2, after: options)
        [loginButton, menuBarButton].forEach { addCheckbox($0) }
        permissionContainer.orientation = .vertical; permissionContainer.alignment = .leading; permissionContainer.spacing = 8; permissionContainer.isHidden = true
        permissionContainer.addArrangedSubview(permissionMessage)
        let permissionButton = NSButton(title: TidyTapStrings.openSystemSettings, target: self, action: #selector(openPermissionSettings)); permissionButton.bezelStyle = .rounded; permissionContainer.addArrangedSubview(permissionButton); stack.addArrangedSubview(permissionContainer)
        let footer = NSStackView(); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 4
        footer.addArrangedSubview(NSTextField(labelWithString: versionText())); footer.addArrangedSubview(linkButton(title: TidyTapStrings.email, url: TidyTapStrings.emailURL)); footer.addArrangedSubview(linkButton(title: TidyTapStrings.github, url: TidyTapStrings.githubURL)); stack.addArrangedSubview(footer)
        apply(settings)
    }

    private func addCheckbox(_ button: NSButton) { button.target = self; button.action = #selector(settingChanged(_:)); button.controlSize = .large; stack.addArrangedSubview(button) }
    func apply(_ settings: TidyTapSettings) {
        self.settings = settings; guard isViewLoaded else { return }
        capsButton.state = settings.capsLockInputSourceSwitching ? .on : .off; wheelButton.state = settings.reverseMouseWheelVertically ? .on : .off; sideButton.state = settings.sideButtonNavigation ? .on : .off; loginButton.state = settings.launchAtLogin ? .on : .off; menuBarButton.state = settings.showInMenuBar ? .on : .off
    }
    func showApplyStatus(_ status: TidyTapApplyStatus) {
        let isPending = status.outcome == .pending
        [capsButton, wheelButton, sideButton, loginButton, menuBarButton].forEach { $0.isEnabled = !isPending }
        switch status.outcome {
        case .pending:
            showPermissionMessage(TidyTapStrings.applyingChanges)
        case .applied:
            showPermissionMessage(TidyTapStrings.changesApplied)
        case .partiallyApplied:
            showPermissionMessage(TidyTapStrings.permissionRequired)
        case .failed:
            showPermissionMessage(status.errorCode?.contains("permissionDenied") == true ? TidyTapStrings.permissionRequired : TidyTapStrings.changesCouldNotBeApplied)
        case .recoveryRequired:
            showPermissionMessage(TidyTapStrings.changesCouldNotBeApplied)
        }
    }
    /// Displays the inline permission/error area; pass nil to hide it.
    func showPermissionMessage(_ message: String?) { permissionMessage.stringValue = message ?? ""; permissionContainer.isHidden = message == nil }
    private func versionText() -> String { let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"; return String(format: TidyTapStrings.versionFormat, version) }
    private func linkButton(title: String, url: URL) -> NSButton { let button = NSButton(title: title, target: self, action: #selector(openLink(_:))); button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString); button.isBordered = false; button.alignment = .left; button.contentTintColor = .linkColor; return button }

    @objc private func settingChanged(_ sender: NSButton) {
        switch sender { case capsButton: settings.capsLockInputSourceSwitching = sender.state == .on; case wheelButton: settings.reverseMouseWheelVertically = sender.state == .on; case sideButton: settings.sideButtonNavigation = sender.state == .on; case loginButton: settings.launchAtLogin = sender.state == .on; case menuBarButton: settings.showInMenuBar = sender.state == .on; default: return }
        // A coordinator may choose to handle this synchronously. The closure
        // is a fallback hook so actions are never delivered twice.
        if delegate?.settingsViewController(self, didChange: settings) != true {
            onSettingsChange?(settings)
        }
    }
    @objc private func openPermissionSettings() {
        if delegate?.settingsViewControllerRequestsPermissionSettings(self) != true {
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
    func settingsViewControllerRequestsPermissionSettings(_ controller: SettingsViewController) -> Bool
}
