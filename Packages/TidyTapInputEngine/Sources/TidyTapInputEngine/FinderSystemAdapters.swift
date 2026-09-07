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

    func selectionSnapshot() -> FinderSelectionSnapshot? {
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
        let context = FinderContext(
            processIdentifier: app.processIdentifier,
            windowIdentifier: CFHash(window)
        )
        return FinderSelectionSnapshot(
            context: context,
            feedbackTarget: selectedFeedbackTarget(in: focused, context: context, budget: &budget)
        )
    }

    func prepareDeferredMove() -> (@Sendable () -> Void)? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return nil
        }
        for event in [down, up] {
            event.flags = [.maskCommand, .maskAlternate]
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        }
        return { [down, up] in
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
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

    private func selectedFeedbackTarget(
        in focused: AXUIElement,
        context: FinderContext,
        budget: inout AXQueryBudget
    ) -> FinderFeedbackTarget? {
        let role = stringAttribute(focused, kAXRoleAttribute, budget: &budget)
        let identifier = stringAttribute(focused, kAXIdentifierAttribute, budget: &budget)
        let selected = elementArrayAttribute(
            focused,
            role == kAXOutlineRole ? kAXSelectedRowsAttribute : kAXSelectedChildrenAttribute,
            budget: &budget
        ) ?? elementArrayAttribute(focused, kAXSelectedRowsAttribute, budget: &budget)
        guard let selected,
              let viewport = elementAttribute(focused, kAXParentAttribute, budget: &budget),
              let viewportRect = rectAttribute(viewport, budget: &budget) else { return nil }

        // The file-list classifier already validated the view. Avoid walking
        // the same ancestors again for every selected icon/column item.
        let prefersName = role == kAXOutlineRole || (identifier != "IconView" && identifier != "GalleryView")
        for item in selected.prefix(12) {
            let candidate = prefersName ? firstFileNameElement(in: item, budget: &budget) ?? item : item
            if let rect = rectAttribute(candidate, budget: &budget),
               rect.intersects(viewportRect), isOnScreen(rect) {
                return FinderFeedbackTarget(
                    context: context,
                    selectionIdentifier: CFHash(item),
                    anchorRect: rect
                )
            }
        }
        return nil
    }

    private func firstFileNameElement(in item: AXUIElement, budget: inout AXQueryBudget) -> AXUIElement? {
        if stringAttribute(item, kAXRoleAttribute, budget: &budget) == kAXTextFieldRole { return item }
        for child in elementArrayAttribute(item, kAXChildrenAttribute, budget: &budget) ?? [] {
            if let name = firstFileNameElement(in: child, budget: &budget) { return name }
        }
        return nil
    }

    private func rectAttribute(_ element: AXUIElement, budget: inout AXQueryBudget) -> CGRect? {
        guard let positionValue = valueAttribute(element, kAXPositionAttribute, budget: &budget),
              let sizeValue = valueAttribute(element, kAXSizeAttribute, budget: &budget) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func isOnScreen(_ rect: CGRect) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { !CGRectIntersection(rect, CGDisplayBounds($0)).isNull }
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

    private func elementArrayAttribute(
        _ element: AXUIElement,
        _ name: String,
        budget: inout AXQueryBudget
    ) -> [AXUIElement]? {
        guard let timeout = budget.timeout(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func valueAttribute(
        _ element: AXUIElement,
        _ name: String,
        budget: inout AXQueryBudget
    ) -> AXValue? {
        guard let timeout = budget.timeout(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
