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
