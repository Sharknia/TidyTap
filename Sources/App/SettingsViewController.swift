import AppKit

/// The single-window settings surface. Persistence and helper coordination are
/// provided by a coordinator through the delegate or closure hooks.
@MainActor
final class SettingsViewController: NSViewController {
    static let contentSize = NSSize(width: 560, height: 650)

    enum RenderingMode {
        case native
        /// NSGlassEffectView and NSVisualEffectView require an ordered window
        /// to composite their backdrop. Offline snapshots use semantic system
        /// surfaces while preserving the production controller and hierarchy.
        case offscreenSemanticFallback
    }

    enum ControlIdentifier {
        static let keyboardGroup = "settings.keyboard.group"
        static let mouseGroup = "settings.mouse.group"
        static let generalGroup = "settings.general.group"
        static let mousePermissions = "settings.mouse.permissions"
        static let capsSwitch = "settings.caps.switch"
        static let wheelSwitch = "settings.wheel.switch"
        static let sideSwitch = "settings.side.switch"
        static let loginSwitch = "settings.login.switch"
        static let accessibilityPermission = "settings.permission.accessibility"
        static let inputMonitoringPermission = "settings.permission.inputMonitoring"
    }

    weak var delegate: SettingsViewControllerDelegate?
    var onSettingsChange: ((TidyTapSettings) -> Void)?
    var onPermissionSettingsRequest: ((TidyTapPermission) -> Void)?

    private(set) var settings: TidyTapSettings
    private(set) var permissionState: TidyTapFeaturePermissionState
    private let appIcon: NSImage
    private let displayVersion: String
    private let renderingMode: RenderingMode
    private let copy: SettingsViewCopy

    private let contentStack = NSStackView()
    private let statusMessage = NSTextField(wrappingLabelWithString: "")
    private let capsSwitch = NSSwitch()
    private let wheelSwitch = NSSwitch()
    private let sideSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let accessibilityStatus: PermissionStatusView
    private let inputMonitoringStatus: PermissionStatusView

    init(
        settings: TidyTapSettings = .defaults,
        permissionState: TidyTapFeaturePermissionState = .init(),
        appIcon: NSImage? = nil,
        displayVersion: String? = nil,
        renderingMode: RenderingMode = .native,
        localizationBundle: Bundle = .main,
        delegate: SettingsViewControllerDelegate? = nil
    ) {
        self.settings = settings
        self.permissionState = permissionState
        self.appIcon = appIcon ?? NSImage(named: "TidyTap") ?? NSApplication.shared.applicationIconImage
        self.displayVersion = displayVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.2"
        self.renderingMode = renderingMode
        let copy = SettingsViewCopy(bundle: localizationBundle)
        self.copy = copy
        accessibilityStatus = PermissionStatusView(permission: .accessibility, copy: copy)
        inputMonitoringStatus = PermissionStatusView(permission: .inputMonitoring, copy: copy)
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root: NSView
        switch renderingMode {
        case .native:
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .withinWindow
            effect.state = .followsWindowActiveState
            root = effect
        case .offscreenSemanticFallback:
            root = SemanticBackgroundView()
        }
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        addHeader()
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)

        addSection(
            title: copy.keyboardSection,
            identifier: ControlIdentifier.keyboardGroup,
            rows: [
                featureRow(
                    symbol: "keyboard",
                    title: copy.capsLockTitle,
                    caption: copy.capsLockCaption,
                    toggle: capsSwitch,
                    identifier: ControlIdentifier.capsSwitch
                )
            ]
        )

        let permissions = permissionBlock()
        addSection(
            title: copy.mouseSection,
            identifier: ControlIdentifier.mouseGroup,
            rows: [
                featureRow(
                    symbol: "computermouse",
                    title: copy.mouseWheelTitle,
                    caption: copy.mouseWheelCaption,
                    toggle: wheelSwitch,
                    identifier: ControlIdentifier.wheelSwitch
                ),
                featureRow(
                    symbol: "arrow.left.arrow.right",
                    title: copy.sideButtonTitle,
                    caption: copy.sideButtonCaption,
                    toggle: sideSwitch,
                    identifier: ControlIdentifier.sideSwitch
                ),
                permissions
            ]
        )

        addSection(
            title: copy.generalSection,
            identifier: ControlIdentifier.generalGroup,
            rows: [
                featureRow(
                    symbol: "power",
                    title: copy.launchAtLogin,
                    caption: copy.launchAtLoginCaption,
                    toggle: loginSwitch,
                    identifier: ControlIdentifier.loginSwitch
                )
            ]
        )

        statusMessage.font = .systemFont(ofSize: 12)
        statusMessage.textColor = .secondaryLabelColor
        statusMessage.maximumNumberOfLines = 2
        statusMessage.isHidden = true
        contentStack.addArrangedSubview(statusMessage)
        statusMessage.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(footer())
        contentStack.arrangedSubviews.last?.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        configureActions()
        apply(settings)
        applyPermissionState(permissionState)
    }

    func apply(_ settings: TidyTapSettings) {
        self.settings = settings
        guard isViewLoaded else { return }
        capsSwitch.state = settings.capsLockInputSourceSwitching ? .on : .off
        wheelSwitch.state = settings.reverseMouseWheelVertically ? .on : .off
        sideSwitch.state = settings.sideButtonNavigation ? .on : .off
        loginSwitch.state = settings.launchAtLogin ? .on : .off
    }

    /// Permission rows always remain visible. Unknown means the helper has not
    /// returned a correlated permission snapshot; it is never presented as allowed.
    func applyPermissionState(_ state: TidyTapFeaturePermissionState) {
        permissionState = state
        guard isViewLoaded else { return }
        accessibilityStatus.apply(state.accessibility)
        inputMonitoringStatus.apply(state.inputMonitoring)
    }

    func showApplyStatus(_ status: TidyTapApplyStatus, permission: TidyTapPermission? = nil) {
        let isPending = status.outcome == .pending
        [capsSwitch, wheelSwitch, sideSwitch, loginSwitch].forEach { $0.isEnabled = !isPending }

        switch status.outcome {
        case .pending:
            showStatus(copy.applyingChanges)
        case .applied:
            showStatus(copy.changesApplied)
        case .partiallyApplied, .failed:
            showStatus(permission == nil ? copy.changesCouldNotBeApplied : copy.reviewPermissions)
        case .recoveryRequired:
            showStatus(copy.changesCouldNotBeApplied)
        }
    }

    /// Compatibility entry point for persistence failures that are not a
    /// permission snapshot. This never changes either displayed permission state.
    func showPermissionMessage(_ message: String?, permission: TidyTapPermission? = nil) {
        showStatus(message)
    }

    private func addHeader() {
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let iconView = NSImageView()
        iconView.image = appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let iconContent = NSView()
        iconContent.translatesAutoresizingMaskIntoConstraints = false
        iconContent.addSubview(iconView)

        let iconGlass = surface(
            content: iconContent,
            cornerRadius: 16,
            tintColor: NSColor.systemTeal.withAlphaComponent(0.09)
        )
        NSLayoutConstraint.activate([
            iconGlass.widthAnchor.constraint(equalToConstant: 58),
            iconGlass.heightAnchor.constraint(equalToConstant: 58),
            iconView.leadingAnchor.constraint(equalTo: iconContent.leadingAnchor, constant: 5),
            iconView.trailingAnchor.constraint(equalTo: iconContent.trailingAnchor, constant: -5),
            iconView.topAnchor.constraint(equalTo: iconContent.topAnchor, constant: 5),
            iconView.bottomAnchor.constraint(equalTo: iconContent.bottomAnchor, constant: -5)
        ])

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let title = NSTextField(labelWithString: copy.appName)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: copy.subtitle)
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)

        header.addArrangedSubview(iconGlass)
        header.addArrangedSubview(labels)
        contentStack.addArrangedSubview(header)
    }

    private func addSection(title: String, identifier: String, rows: [NSView]) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.identifier = NSUserInterfaceItemIdentifier(identifier + ".section")

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        section.addArrangedSubview(label)

        let cardContent = NSStackView()
        cardContent.orientation = .vertical
        cardContent.alignment = .leading
        cardContent.spacing = 0
        cardContent.translatesAutoresizingMaskIntoConstraints = false

        for (index, row) in rows.enumerated() {
            if index > 0 {
                cardContent.addArrangedSubview(separator())
            }
            cardContent.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: cardContent.widthAnchor).isActive = true
        }

        let card = surface(content: cardContent, cornerRadius: 14)
        card.identifier = NSUserInterfaceItemIdentifier(identifier)
        section.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func featureRow(
        symbol: String,
        title: String,
        caption: String,
        toggle: NSSwitch,
        identifier: String
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = symbolImageView(symbol)
        let labels = rowLabels(title: title, caption: caption)
        toggle.identifier = NSUserInterfaceItemIdentifier(identifier)
        toggle.setAccessibilityLabel(title)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        [icon, labels, toggle].forEach(row.addSubview)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 60),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func surface(
        content: NSView,
        cornerRadius: CGFloat,
        tintColor: NSColor? = nil
    ) -> NSView {
        switch renderingMode {
        case .native:
            return GlassCardView(content: content, cornerRadius: cornerRadius, tintColor: tintColor)
        case .offscreenSemanticFallback:
            return SemanticSurfaceView(content: content, cornerRadius: cornerRadius)
        }
    }

    private func permissionBlock() -> NSView {
        let block = NSView()
        block.identifier = NSUserInterfaceItemIdentifier(ControlIdentifier.mousePermissions)
        block.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: copy.mousePermissionsTitle)
        heading.font = .systemFont(ofSize: 11, weight: .medium)
        heading.textColor = .tertiaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        block.addSubview(heading)
        block.addSubview(stack)
        stack.addArrangedSubview(accessibilityStatus)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(inputMonitoringStatus)

        NSLayoutConstraint.activate([
            block.heightAnchor.constraint(equalToConstant: 122),
            heading.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 18),
            heading.topAnchor.constraint(equalTo: block.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: block.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: block.trailingAnchor),
            stack.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: block.bottomAnchor),
            accessibilityStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            inputMonitoringStatus.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return block
    }

    private func configureActions() {
        [capsSwitch, wheelSwitch, sideSwitch, loginSwitch].forEach {
            $0.target = self
            $0.action = #selector(settingChanged(_:))
        }
        accessibilityStatus.button.target = self
        accessibilityStatus.button.action = #selector(requestPermission(_:))
        inputMonitoringStatus.button.target = self
        inputMonitoringStatus.button.action = #selector(requestPermission(_:))
    }

    private func footer() -> NSView {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let version = NSTextField(labelWithString: versionText())
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        footer.addArrangedSubview(version)
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(linkButton(title: TidyTapStrings.email, url: TidyTapStrings.emailURL))
        let dot = NSTextField(labelWithString: "·")
        dot.textColor = .tertiaryLabelColor
        footer.addArrangedSubview(dot)
        footer.addArrangedSubview(linkButton(title: copy.githubShort, url: TidyTapStrings.githubURL))
        return footer
    }

    private func rowLabels(title: String, caption: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(captionLabel)
        return stack
    }

    private func symbolImageView(_ symbol: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        view.contentTintColor = .secondaryLabelColor
        view.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func showStatus(_ message: String?) {
        statusMessage.stringValue = message ?? ""
        statusMessage.isHidden = message?.isEmpty != false
    }

    private func versionText() -> String {
        String(format: copy.versionFormat, displayVersion)
    }

    private func linkButton(title: String, url: URL) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    @objc private func settingChanged(_ sender: NSSwitch) {
        switch sender {
        case capsSwitch:
            settings.capsLockInputSourceSwitching = sender.state == .on
        case wheelSwitch:
            settings.reverseMouseWheelVertically = sender.state == .on
        case sideSwitch:
            settings.sideButtonNavigation = sender.state == .on
        case loginSwitch:
            settings.launchAtLogin = sender.state == .on
        default:
            return
        }

        if delegate?.settingsViewController(self, didChange: settings) != true {
            onSettingsChange?(settings)
        }
    }

    @objc private func requestPermission(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let permission = TidyTapPermission(rawValue: rawValue) else {
            return
        }
        if delegate?.settingsViewControllerRequestsPermissionSettings(self, permission: permission) != true {
            onPermissionSettingsRequest?(permission)
        }
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue,
              let url = URL(string: value) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsViewCopy {
    let appName: String
    let subtitle: String
    let keyboardSection: String
    let mouseSection: String
    let generalSection: String
    let capsLockTitle: String
    let capsLockCaption: String
    let mouseWheelTitle: String
    let mouseWheelCaption: String
    let sideButtonTitle: String
    let sideButtonCaption: String
    let launchAtLogin: String
    let launchAtLoginCaption: String
    let versionFormat: String
    let mousePermissionsTitle: String
    let accessibilityPermissionTitle: String
    let accessibilityPermissionCaption: String
    let inputMonitoringPermissionTitle: String
    let inputMonitoringPermissionCaption: String
    let permissionAllowed: String
    let permissionMissing: String
    let permissionNotChecked: String
    let permissionSettingsAction: String
    let openAccessibilitySettings: String
    let openInputMonitoringSettings: String
    let applyingChanges: String
    let changesApplied: String
    let changesCouldNotBeApplied: String
    let reviewPermissions: String
    let githubShort: String

    init(bundle: Bundle) {
        func text(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: key, table: nil)
        }

        appName = text("TidyTap")
        subtitle = text("Keyboard and mouse, simply")
        keyboardSection = text("Keyboard")
        mouseSection = text("Mouse")
        generalSection = text("General")
        capsLockTitle = text("Caps Lock input switching")
        capsLockCaption = text("Switch input sources without changing letter case")
        mouseWheelTitle = text("Reverse wheel direction")
        mouseWheelCaption = text("Keep trackpad scrolling unchanged")
        sideButtonTitle = text("Side-button navigation")
        sideButtonCaption = text("Back and forward in Safari and Finder")
        launchAtLogin = text("Start at login")
        launchAtLoginCaption = text("Keep TidyTap ready after you sign in")
        versionFormat = text("Version %@")
        mousePermissionsTitle = text("PERMISSIONS FOR MOUSE FEATURES")
        accessibilityPermissionTitle = text("Accessibility")
        accessibilityPermissionCaption = text("Required for wheel reversal and side buttons")
        inputMonitoringPermissionTitle = text("Input Monitoring")
        inputMonitoringPermissionCaption = text("Required for wheel reversal only")
        permissionAllowed = text("Allowed")
        permissionMissing = text("Missing")
        permissionNotChecked = text("Not checked")
        permissionSettingsAction = text("Settings")
        openAccessibilitySettings = text("Open Accessibility Settings")
        openInputMonitoringSettings = text("Open Input Monitoring Settings")
        applyingChanges = text("Applying changes…")
        changesApplied = text("Changes applied.")
        changesCouldNotBeApplied = text("Changes could not be applied.")
        reviewPermissions = text("Review the mouse permission status below.")
        githubShort = "GitHub"
    }
}

@MainActor
private final class PermissionStatusView: NSView {
    let button: NSButton
    private let copy: SettingsViewCopy
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(permission: TidyTapPermission, copy: SettingsViewCopy) {
        self.copy = copy
        button = NSButton(title: copy.permissionSettingsAction, target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier(
            permission == .accessibility
                ? SettingsViewController.ControlIdentifier.accessibilityPermission
                : SettingsViewController.ControlIdentifier.inputMonitoringPermission
        )

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: permission == .accessibility
            ? copy.accessibilityPermissionTitle
            : copy.inputMonitoringPermissionTitle)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let caption = NSTextField(labelWithString: permission == .accessibility
            ? copy.accessibilityPermissionCaption
            : copy.inputMonitoringPermissionCaption)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(caption)

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let status = NSStackView(views: [statusIcon, statusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 4
        status.translatesAutoresizingMaskIntoConstraints = false

        button.identifier = NSUserInterfaceItemIdentifier(permission.rawValue)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.setAccessibilityLabel(permission == .accessibility
            ? copy.openAccessibilitySettings
            : copy.openInputMonitoringSettings)
        button.translatesAutoresizingMaskIntoConstraints = false

        [statusIcon, labels, status, button].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            statusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            statusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 18),
            statusIcon.heightAnchor.constraint(equalToConstant: 18),
            labels.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: labels.trailingAnchor, constant: 12),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ state: TidyTapPermissionState) {
        switch state {
        case .unknown:
            statusIcon.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            statusIcon.contentTintColor = .secondaryLabelColor
            statusLabel.stringValue = copy.permissionNotChecked
            statusLabel.textColor = .secondaryLabelColor
        case .authorized:
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = copy.permissionAllowed
            statusLabel.textColor = .systemGreen
        case .denied:
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.stringValue = copy.permissionMissing
            statusLabel.textColor = .systemOrange
        }
        setAccessibilityValue(statusLabel.stringValue)
    }
}

/// A compact, system-rendered glass surface. All card content is assigned via
/// `contentView`; arbitrary subviews are deliberately not layered over the glass.
@MainActor
private final class GlassCardView: NSGlassEffectView {
    init(content: NSView, cornerRadius: CGFloat, tintColor: NSColor?) {
        super.init(frame: .zero)
        style = .regular
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor ?? NSColor.controlBackgroundColor.withAlphaComponent(0.055)
        translatesAutoresizingMaskIntoConstraints = false
        contentView = content
        wantsLayer = true
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }
}

@MainActor
private final class SemanticBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

@MainActor
private final class SemanticSurfaceView: NSView {
    init(content: NSView, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 0.5
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }
    }
}

@MainActor
protocol SettingsViewControllerDelegate: AnyObject {
    /// Return true when the delegate handled the action; false selects the
    /// controller's closure fallback.
    func settingsViewController(_ controller: SettingsViewController, didChange settings: TidyTapSettings) -> Bool
    func settingsViewControllerRequestsPermissionSettings(_ controller: SettingsViewController, permission: TidyTapPermission) -> Bool
}
