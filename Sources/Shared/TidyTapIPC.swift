import Foundation

enum TidyTapFinderFeedbackKind: String {
    case moveReady
    case copyReady
}

struct TidyTapFinderFeedbackPayload {
    let kind: TidyTapFinderFeedbackKind
    let anchorRect: CGRect
    let clipboardChangeCount: Int
}

/// Names and payload rules shared by the settings app and the background helper.
enum TidyTapIPC {
    static let settingsDidChange = Notification.Name("com.sharknia.TidyTap.settingsDidChange")
    static let applyResult = Notification.Name("com.sharknia.TidyTap.applyResult")
    static let permissionRequest = Notification.Name("com.sharknia.TidyTap.permissionRequest")
    static let permissionResult = Notification.Name("com.sharknia.TidyTap.permissionResult")
    static let finderFeedback = Notification.Name("com.sharknia.TidyTap.finderFeedback")
    static let finderFeedbackReady = Notification.Name("com.sharknia.TidyTap.finderFeedbackReady")
    static let clipboardHistoryToggle = Notification.Name("com.sharknia.TidyTap.clipboardHistoryToggle")
    static let clipboardHistoryChanged = Notification.Name("com.sharknia.TidyTap.clipboardHistoryChanged")
    static let clipboardHistoryPaste = Notification.Name("com.sharknia.TidyTap.clipboardHistoryPaste")
    static let clipboardHistoryPasteResult = Notification.Name("com.sharknia.TidyTap.clipboardHistoryPasteResult")
    static let prepareForUpdate = Notification.Name("com.sharknia.TidyTap.prepareForUpdate")
    static let clipboardTargetPIDEnvironmentKey = "TIDYTAP_CLIPBOARD_TARGET_PID"
    static let clipboardSessionEnvironmentKey = "TIDYTAP_CLIPBOARD_SESSION"
    static let clipboardHistoryModeEnvironmentKey = "TIDYTAP_CLIPBOARD_HISTORY_MODE"
    static let clipboardDisplayIDEnvironmentKey = "TIDYTAP_CLIPBOARD_DISPLAY_ID"
    static let clipboardTargetPIDUserInfoKey = "targetPID"
    static let clipboardSessionUserInfoKey = "sessionID"
    static let clipboardDisplayIDUserInfoKey = "displayID"
    static let clipboardEntryUserInfoKey = "entryID"
    static let clipboardFormattedUserInfoKey = "formatted"
    static let clipboardPasteErrorUserInfoKey = "error"
    static let applyRequestIDUserInfoKey = "applyRequestID"
    static let finderFeedbackModeEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_MODE"
    static let finderFeedbackKindEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_KIND"
    static let finderFeedbackMinXEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_MIN_X"
    static let finderFeedbackMinYEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_MIN_Y"
    static let finderFeedbackWidthEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_WIDTH"
    static let finderFeedbackHeightEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_HEIGHT"
    static let finderFeedbackNonceEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_NONCE"
    static let finderFeedbackChangeCountEnvironmentKey = "TIDYTAP_FINDER_FEEDBACK_CHANGE_COUNT"

    private static let finderFeedbackKindUserInfoKey = "kind"
    private static let finderFeedbackMinXUserInfoKey = "minX"
    private static let finderFeedbackMinYUserInfoKey = "minY"
    private static let finderFeedbackWidthUserInfoKey = "width"
    private static let finderFeedbackHeightUserInfoKey = "height"
    private static let finderFeedbackNonceUserInfoKey = "nonce"
    private static let finderFeedbackProcessIDUserInfoKey = "processID"
    private static let finderFeedbackChangeCountUserInfoKey = "changeCount"

    static func postSettingsDidChange(requestID: UUID) {
        post(settingsDidChange, requestID: requestID)
    }

    static func postPrepareForUpdate() {
        DistributedNotificationCenter.default().postNotificationName(
            prepareForUpdate,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postApplyResult(_ status: TidyTapApplyStatus) {
        post(applyResult, requestID: status.applyRequestID)
    }

    static func postPermissionRequest(_ request: TidyTapPermissionRequest) {
        post(permissionRequest, requestID: request.requestID)
    }

    static func postPermissionResult(_ result: TidyTapPermissionResult) {
        post(permissionResult, requestID: result.requestID)
    }

    static func requestID(in notification: Notification) -> UUID? {
        guard let rawID = notification.userInfo?[applyRequestIDUserInfoKey] as? String else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    static func postFinderFeedback(_ payload: TidyTapFinderFeedbackPayload) {
        DistributedNotificationCenter.default().postNotificationName(
            finderFeedback,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: finderFeedbackUserInfo(payload),
            deliverImmediately: true
        )
    }

    static func postClipboardHistoryToggle(targetPID: pid_t, sessionID: UUID, displayID: UInt32?) {
        var info: [String: Any] = [
            clipboardTargetPIDUserInfoKey: targetPID,
            clipboardSessionUserInfoKey: sessionID.uuidString
        ]
        if let displayID { info[clipboardDisplayIDUserInfoKey] = displayID }
        DistributedNotificationCenter.default().postNotificationName(
            clipboardHistoryToggle,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: info,
            deliverImmediately: true
        )
    }

    static func postClipboardHistoryPaste(sessionID: UUID, entryID: UUID, formatted: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            clipboardHistoryPaste,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: [
                clipboardSessionUserInfoKey: sessionID.uuidString,
                clipboardEntryUserInfoKey: entryID.uuidString,
                clipboardFormattedUserInfoKey: formatted
            ],
            deliverImmediately: true
        )
    }

    static func clipboardPasteRequest(in notification: Notification) -> (sessionID: UUID, entryID: UUID, formatted: Bool)? {
        guard let info = notification.userInfo,
              let session = info[clipboardSessionUserInfoKey] as? String,
              let sessionID = UUID(uuidString: session),
              let entry = info[clipboardEntryUserInfoKey] as? String,
              let entryID = UUID(uuidString: entry),
              let formatted = info[clipboardFormattedUserInfoKey] as? Bool else { return nil }
        return (sessionID, entryID, formatted)
    }

    static func postClipboardHistoryPasteResult(sessionID: UUID, error: String?) {
        DistributedNotificationCenter.default().postNotificationName(
            clipboardHistoryPasteResult,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: [
                clipboardSessionUserInfoKey: sessionID.uuidString,
                clipboardPasteErrorUserInfoKey: error ?? ""
            ],
            deliverImmediately: true
        )
    }

    static func clipboardPasteResult(in notification: Notification) -> (sessionID: UUID, error: String?)? {
        guard let info = notification.userInfo,
              let session = info[clipboardSessionUserInfoKey] as? String,
              let sessionID = UUID(uuidString: session),
              let error = info[clipboardPasteErrorUserInfoKey] as? String else { return nil }
        return (sessionID, error.isEmpty ? nil : error)
    }

    static func postClipboardHistoryChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            clipboardHistoryChanged,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func clipboardTargetPID(in notification: Notification) -> pid_t? {
        (notification.userInfo?[clipboardTargetPIDUserInfoKey] as? NSNumber)?.int32Value
    }

    static func clipboardTargetPID(in environment: [String: String]) -> pid_t? {
        environment[clipboardTargetPIDEnvironmentKey].flatMap(Int32.init)
    }

    static func clipboardSessionID(in notification: Notification) -> UUID? {
        (notification.userInfo?[clipboardSessionUserInfoKey] as? String).flatMap(UUID.init(uuidString:))
    }

    static func clipboardSessionID(in environment: [String: String]) -> UUID? {
        environment[clipboardSessionEnvironmentKey].flatMap(UUID.init(uuidString:))
    }

    static func clipboardDisplayID(in notification: Notification) -> UInt32? {
        (notification.userInfo?[clipboardDisplayIDUserInfoKey] as? NSNumber)?.uint32Value
    }

    static func clipboardDisplayID(in environment: [String: String]) -> UInt32? {
        environment[clipboardDisplayIDEnvironmentKey].flatMap(UInt32.init)
    }

    static func finderFeedback(in notification: Notification) -> TidyTapFinderFeedbackPayload? {
        guard let userInfo = notification.userInfo,
              let rawKind = userInfo[finderFeedbackKindUserInfoKey] as? String,
              let kind = TidyTapFinderFeedbackKind(rawValue: rawKind),
              let minX = userInfo[finderFeedbackMinXUserInfoKey] as? NSNumber,
              let minY = userInfo[finderFeedbackMinYUserInfoKey] as? NSNumber,
              let width = userInfo[finderFeedbackWidthUserInfoKey] as? NSNumber,
              let height = userInfo[finderFeedbackHeightUserInfoKey] as? NSNumber,
              let changeCount = userInfo[finderFeedbackChangeCountUserInfoKey] as? NSNumber else { return nil }
        return .init(
            kind: kind,
            anchorRect: CGRect(x: minX.doubleValue, y: minY.doubleValue, width: width.doubleValue, height: height.doubleValue),
            clipboardChangeCount: changeCount.intValue
        )
    }

    static func finderFeedback(in environment: [String: String]) -> TidyTapFinderFeedbackPayload? {
        guard environment[finderFeedbackModeEnvironmentKey] == "1",
              let rawKind = environment[finderFeedbackKindEnvironmentKey],
              let kind = TidyTapFinderFeedbackKind(rawValue: rawKind),
              let minX = environment[finderFeedbackMinXEnvironmentKey].flatMap(Double.init),
              let minY = environment[finderFeedbackMinYEnvironmentKey].flatMap(Double.init),
              let width = environment[finderFeedbackWidthEnvironmentKey].flatMap(Double.init),
              let height = environment[finderFeedbackHeightEnvironmentKey].flatMap(Double.init),
              let changeCount = environment[finderFeedbackChangeCountEnvironmentKey].flatMap(Int.init) else { return nil }
        return .init(
            kind: kind,
            anchorRect: CGRect(x: minX, y: minY, width: width, height: height),
            clipboardChangeCount: changeCount
        )
    }

    static func finderFeedbackEnvironment(_ payload: TidyTapFinderFeedbackPayload) -> [String: String] {
        [
            finderFeedbackModeEnvironmentKey: "1",
            finderFeedbackKindEnvironmentKey: payload.kind.rawValue,
            finderFeedbackMinXEnvironmentKey: String(Double(payload.anchorRect.minX)),
            finderFeedbackMinYEnvironmentKey: String(Double(payload.anchorRect.minY)),
            finderFeedbackWidthEnvironmentKey: String(Double(payload.anchorRect.width)),
            finderFeedbackHeightEnvironmentKey: String(Double(payload.anchorRect.height)),
            finderFeedbackChangeCountEnvironmentKey: String(payload.clipboardChangeCount),
        ]
    }

    static func postFinderFeedbackReady(nonce: UUID? = nil, processID: pid_t = getpid()) {
        var userInfo: [String: Any] = [finderFeedbackProcessIDUserInfoKey: processID]
        if let nonce {
            userInfo[finderFeedbackNonceUserInfoKey] = nonce.uuidString
        }
        DistributedNotificationCenter.default().postNotificationName(
            finderFeedbackReady,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    static func finderFeedbackReady(in notification: Notification) -> (nonce: UUID?, processID: pid_t)? {
        guard let processNumber = notification.userInfo?[finderFeedbackProcessIDUserInfoKey] as? NSNumber else {
            return nil
        }
        let nonce = (notification.userInfo?[finderFeedbackNonceUserInfoKey] as? String)
            .flatMap(UUID.init(uuidString:))
        return (nonce, processNumber.int32Value)
    }

    private static func finderFeedbackUserInfo(_ payload: TidyTapFinderFeedbackPayload) -> [String: Any] {
        [
            finderFeedbackKindUserInfoKey: payload.kind.rawValue,
            finderFeedbackMinXUserInfoKey: payload.anchorRect.minX,
            finderFeedbackMinYUserInfoKey: payload.anchorRect.minY,
            finderFeedbackWidthUserInfoKey: payload.anchorRect.width,
            finderFeedbackHeightUserInfoKey: payload.anchorRect.height,
            finderFeedbackChangeCountUserInfoKey: payload.clipboardChangeCount,
        ]
    }

    private static func post(_ name: Notification.Name, requestID: UUID) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: [applyRequestIDUserInfoKey: requestID.uuidString],
            deliverImmediately: true
        )
    }
}
