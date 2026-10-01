import AppKit

/// Shows a short-lived, non-interactive confirmation beside a Finder item.
///
/// `anchorRect` is in the global Accessibility coordinate system: its origin
/// is measured from the top-left of the global screen arrangement.
@MainActor
final class FinderFeedbackPanelController: NSObject {
    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private let messageLabel: NSTextField
    private var hideTimer: Timer?

    override init() {
        effectView = NSVisualEffectView(frame: .zero)
        messageLabel = NSTextField(labelWithString: "")
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byClipping

        panel.contentView = effectView
        effectView.addSubview(messageLabel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(message: String, anchorRect: CGRect) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard !message.isEmpty, let screen = screen(for: anchorRect) else {
            hide()
            return
        }

        messageLabel.stringValue = message
        let labelSize = messageLabel.intrinsicContentSize
        let panelSize = NSSize(
            width: max(1, labelSize.width + 20),
            height: max(1, labelSize.height + 10)
        )
        effectView.frame = NSRect(origin: .zero, size: panelSize)
        messageLabel.frame = NSRect(
            x: 10,
            y: 5,
            width: panelSize.width - 20,
            height: panelSize.height - 10
        )

        let globalTop = globalScreenTop
        let anchorTopLeft = NSPoint(
            x: anchorRect.minX,
            y: globalTop - anchorRect.minY
        )
        let visibleFrame = screen.visibleFrame
        var origin = NSPoint(
            x: anchorRect.maxX + 8,
            y: anchorTopLeft.y - panelSize.height
        )
        origin.x = min(
            max(origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.orderFrontRegardless()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(hideTimerFired),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }

    @objc private func hideTimerFired() {
        hide()
    }

    private var globalScreenTop: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private func screen(for anchorRect: CGRect) -> NSScreen? {
        let anchorPoint = NSPoint(
            x: anchorRect.midX,
            y: globalScreenTop - anchorRect.midY
        )
        return NSScreen.screens.first { $0.frame.contains(anchorPoint) }
    }
}

/// Passive paste feedback uses the same system materials as Settings.
@MainActor
final class ClipboardPasteFeedbackPanelController {
    private final class PassivePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    init() {
        panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        let content = NSView()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 8
            glass.contentView = content
            panel.contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 8
            effect.layer?.masksToBounds = true
            panel.contentView = effect
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
        }
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(message: String, on screen: NSScreen?) {
        guard let screen = screen.flatMap({ requested in
            NSScreen.screens.first { $0 == requested }
        }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        hideTimer?.invalidate()
        label.stringValue = message
        let size = NSSize(width: label.intrinsicContentSize.width + 24,
                          height: label.intrinsicContentSize.height + 16)
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height - 12,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        let timer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }
}
