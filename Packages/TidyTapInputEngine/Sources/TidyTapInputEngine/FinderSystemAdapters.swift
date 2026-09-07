@preconcurrency import AppKit
import ApplicationServices
import Foundation

struct AXQueryBudget {
    let deadline: TimeInterval
    let perCallTimeout: TimeInterval

    init(startedAt: TimeInterval, total: TimeInterval = 0.03, perCall: TimeInterval = 0.005) {
        deadline = startedAt + total
        perCallTimeout = perCall
    }

    func timeout(at now: TimeInterval) -> Float? {
        let remaining = deadline - now
        guard remaining > 0 else { return nil }
        return Float(min(perCallTimeout, remaining))
    }
}

final class FinderSystemEnvironment: FinderCutPasteEnvironment, @unchecked Sendable {
    private static let syntheticEventMarker: Int64 = 0x5449_4459_5441_50

    func focusedFileListContext() -> FinderContext? {
        var budget = AXQueryBudget(startedAt: ProcessInfo.processInfo.systemUptime)
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.finder" else {
            return nil
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = elementAttribute(application, kAXFocusedUIElementAttribute, budget: &budget),
              let window = elementAttribute(application, kAXFocusedWindowAttribute, budget: &budget),
              isFileList(focused, budget: &budget) else {
            return nil
        }
        return FinderContext(
            processIdentifier: app.processIdentifier,
            windowIdentifier: CFHash(window)
        )
    }

    func pasteboardSnapshot() -> FinderPasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        let containsFiles = pasteboard.availableType(from: [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]) != nil
        return FinderPasteboardSnapshot(changeCount: changeCount, containsFiles: containsFiles)
    }

    func sendDeferredMove() -> Bool {
        guard focusedFileListContext() != nil,
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        for event in [down, up] {
            event.flags = [.maskCommand, .maskAlternate]
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
    }

    private func isFileList(_ focused: AXUIElement, budget: inout AXQueryBudget) -> Bool {
        guard let role = stringAttribute(focused, kAXRoleAttribute, budget: &budget) else {
            return false
        }
        let identifier = stringAttribute(focused, kAXIdentifierAttribute, budget: &budget)
        if role == kAXOutlineRole && identifier == "ListView" { return true }
        if role == kAXListRole && ["IconView", "GalleryView"].contains(identifier) { return true }
        guard role == kAXListRole else { return false }

        var current = elementAttribute(focused, kAXParentAttribute, budget: &budget)
        for _ in 0..<7 {
            guard let element = current else { return false }
            if stringAttribute(element, kAXRoleAttribute, budget: &budget) == kAXBrowserRole,
               stringAttribute(element, kAXIdentifierAttribute, budget: &budget) == "ColumnView" {
                return true
            }
            current = elementAttribute(element, kAXParentAttribute, budget: &budget)
        }
        return false
    }

    private func stringAttribute(
        _ element: AXUIElement,
        _ name: String,
        budget: inout AXQueryBudget
    ) -> String? {
        guard let timeout = budget.timeout(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func elementAttribute(
        _ element: AXUIElement,
        _ name: String,
        budget: inout AXQueryBudget
    ) -> AXUIElement? {
        guard let timeout = budget.timeout(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
