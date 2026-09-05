import Foundation

/// Names and payload rules shared by the settings app and the background helper.
enum TidyTapIPC {
    static let settingsDidChange = Notification.Name("com.sharknia.TidyTap.settingsDidChange")
    static let applyResult = Notification.Name("com.sharknia.TidyTap.applyResult")
    static let permissionRequest = Notification.Name("com.sharknia.TidyTap.permissionRequest")
    static let permissionResult = Notification.Name("com.sharknia.TidyTap.permissionResult")
    static let applyRequestIDUserInfoKey = "applyRequestID"

    static func postSettingsDidChange(requestID: UUID) {
        post(settingsDidChange, requestID: requestID)
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

    private static func post(_ name: Notification.Name, requestID: UUID) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: TidyTapProduct.appBundleIdentifier,
            userInfo: [applyRequestIDUserInfoKey: requestID.uuidString],
            deliverImmediately: true
        )
    }
}
