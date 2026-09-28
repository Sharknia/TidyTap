import Foundation

/// Centralized UI strings keep Korean and English copy consistent.
enum TidyTapStrings {
    static let appName = String(localized: "TidyTap", bundle: .main)
    static let quitApp = String(localized: "Quit TidyTap", bundle: .main)
    static let capsLockInputSourceSwitching = String(localized: "Use Caps Lock to switch input source", bundle: .main)
    static let finderCutPaste = String(localized: "Use cut in Finder", bundle: .main)
    static let finderCutPasteDescription = String(localized: "Cut with ⌘X and move with ⌘V", bundle: .main)
    static let finderMoveReady = String(localized: "Move ready", bundle: .main)
    static let finderCopyReady = String(localized: "Copy ready", bundle: .main)
    static let reverseMouseWheelVertically = String(localized: "Reverse vertical mouse wheel direction", bundle: .main)
    static let fixedMouseWheelStepSize = String(localized: "Fixed wheel step size", bundle: .main)
    static let fixedMouseWheelStepSizeDescription = String(localized: "Scroll a consistent amount for each wheel click", bundle: .main)
    static let mouseWheelStepSize = String(localized: "Step size", bundle: .main)
    static func mouseWheelStepLines(_ lines: Int) -> String {
        lines == 1 ? String(localized: "1 line", bundle: .main)
            : String(format: String(localized: "%d lines", bundle: .main), lines)
    }
    static let sideButtonNavigation = String(localized: "Use side buttons for back/forward in Safari and Finder", bundle: .main)
    static let options = String(localized: "Options", bundle: .main)
    static let launchAtLogin = String(localized: "Start at login", bundle: .main)
    static let versionFormat = String(localized: "Version %@", bundle: .main)
    static let permissionRequired = String(localized: "Permission is required for this feature.", bundle: .main)
    static let accessibilityPermissionRequired = String(localized: "Accessibility is required. In System Settings > Privacy & Security > Accessibility, enable TidyTap. Return here; TidyTap will refresh to confirm access. Then turn your desired feature back on.", bundle: .main)
    static let inputMonitoringPermissionRequired = String(localized: "Input Monitoring is required. In System Settings > Privacy & Security > Input Monitoring, enable TidyTap. Return here; TidyTap will refresh to confirm access. Then turn your desired feature back on.", bundle: .main)
    static let openAccessibilitySettings = String(localized: "Open Accessibility Settings", bundle: .main)
    static let openInputMonitoringSettings = String(localized: "Open Input Monitoring Settings", bundle: .main)
    static let applyingChanges = String(localized: "Applying changes…", bundle: .main)
    static let changesApplied = String(localized: "Changes applied.", bundle: .main)
    static let changesCouldNotBeApplied = String(localized: "Changes could not be applied.", bundle: .main)
    static func clipboardPasteFailureMessage(for reason: String?, bundle: Bundle = .main) -> String {
        return switch reason {
        case "entryUnavailable": String(localized: "The selected history item is no longer available. Reopen history and try again.", bundle: bundle)
        case "eventUnavailable": String(localized: "TidyTap could not send the paste shortcut. Check Accessibility permission and try again.", bundle: bundle)
        case "pasteboardWriteFailed": String(localized: "TidyTap could not write the selected item to the clipboard. Try again.", bundle: bundle)
        case "helperTimeout": String(localized: "TidyTap Helper did not respond. Reopen history and try again.", bundle: bundle)
        case "targetUnavailable": String(localized: "The original app is no longer active. Reopen history from the input field and try again.", bundle: bundle)
        case "focusChanged": String(localized: "The original input field could not be confirmed or its focus changed. Reopen history from the field you want to paste into.", bundle: bundle)
        default: String(localized: "Return to the original input field and try again.", bundle: bundle)
        }
    }
    static func capsLockApplyMessage(for status: TidyTapApplyStatus, bundle: Bundle = .main) -> String? {
        guard status.outcome == .failed || status.outcome == .recoveryRequired else { return nil }

        if status.outcome == .recoveryRequired, hasCapsLockRollbackFailure(status.errorCode) {
            return String(localized: "Caps Lock changes need to be restored before you continue.", bundle: bundle)
        }

        guard status.failedComponent == .capsLock else { return nil }

        if status.errorCode?.hasPrefix("capsLock.recoveryRequired.") == true {
            return String(localized: "Caps Lock changes need to be restored before you continue.", bundle: bundle)
        }

        guard let errorCode = status.errorCode else { return nil }
        if errorCode.hasPrefix("capsLock.invalidInputSourceCount.") {
            return String(localized: "Caps Lock input switching requires exactly two enabled input sources.", bundle: bundle)
        }
        switch errorCode {
        case "capsLock.conflict.sourceMapping":
            return String(localized: "Caps Lock already has a key mapping. Check the existing mapping before trying again.", bundle: bundle)
        case "capsLock.conflict.hidOwnership", "capsLock.conflict.symbolicHotkey":
            return String(localized: "TidyTap cannot change the Caps Lock setting because another configuration owns it.", bundle: bundle)
        default:
            break
        }
        if errorCode.hasPrefix("capsLock.invalidSystemData.") {
            return String(localized: "TidyTap could not read the current Caps Lock keyboard settings.", bundle: bundle)
        }
        if errorCode.hasPrefix("capsLock.verificationFailed.") {
            return String(localized: "TidyTap could not verify the Caps Lock setting after applying it.", bundle: bundle)
        }
        return nil
    }

    private static func hasCapsLockRollbackFailure(_ errorCode: String?) -> Bool {
        let prefix = "lifecycle.rollbackFailed."
        guard let errorCode, errorCode.hasPrefix(prefix) else { return false }
        return errorCode.dropFirst(prefix.count).split(separator: ".").contains("capsLock")
    }
    static let email = "zel@kakao.com"
    static let emailURL = URL(string: "mailto:zel@kakao.com")!
    static let github = "github.com/Sharknia/TidyTap"
    static let githubURL = URL(string: "https://github.com/Sharknia/TidyTap")!
}
