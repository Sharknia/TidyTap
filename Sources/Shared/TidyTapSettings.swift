import Foundation

/// The complete user-configurable state for the 0.0.2 preferences domain.
struct TidyTapSettings: Codable, Equatable {
    var capsLockInputSourceSwitching: Bool
    var reverseMouseWheelVertically: Bool
    var sideButtonNavigation: Bool
    var launchAtLogin: Bool
    /// Applies a fixed logical line delta to eligible discrete mouse-wheel
    /// events. This is intentionally independent from direction reversal.
    var fixedMouseWheelStepEnabled: Bool
    /// The remembered fixed-wheel step, even while the feature is disabled or
    /// unavailable because permissions were revoked.
    var mouseWheelStepLines: Int {
        get { normalizedMouseWheelStepLines }
        set { normalizedMouseWheelStepLines = Self.normalizedMouseWheelStepLines(newValue) }
    }
    private var normalizedMouseWheelStepLines: Int

    static let mouseWheelStepLineRange = 1...10
    static let defaultMouseWheelStepLines = 3

    init(
        capsLockInputSourceSwitching: Bool,
        reverseMouseWheelVertically: Bool,
        sideButtonNavigation: Bool,
        launchAtLogin: Bool,
        fixedMouseWheelStepEnabled: Bool = false,
        mouseWheelStepLines: Int = Self.defaultMouseWheelStepLines
    ) {
        self.capsLockInputSourceSwitching = capsLockInputSourceSwitching
        self.reverseMouseWheelVertically = reverseMouseWheelVertically
        self.sideButtonNavigation = sideButtonNavigation
        self.launchAtLogin = launchAtLogin
        self.fixedMouseWheelStepEnabled = fixedMouseWheelStepEnabled
        self.normalizedMouseWheelStepLines = Self.normalizedMouseWheelStepLines(mouseWheelStepLines)
    }

    static let defaults = TidyTapSettings(
        capsLockInputSourceSwitching: false,
        reverseMouseWheelVertically: false,
        sideButtonNavigation: false,
        launchAtLogin: false,
        fixedMouseWheelStepEnabled: false,
        mouseWheelStepLines: defaultMouseWheelStepLines
    )

    /// The login-item preference alone must not keep a helper process alive.
    var requiresHelper: Bool {
        capsLockInputSourceSwitching ||
            reverseMouseWheelVertically ||
            fixedMouseWheelStepEnabled ||
            sideButtonNavigation
    }

    private enum CodingKeys: String, CodingKey {
        case capsLockInputSourceSwitching
        case reverseMouseWheelVertically
        case sideButtonNavigation
        case launchAtLogin
        case fixedMouseWheelStepEnabled
        case mouseWheelStepLines
    }

    /// New wheel-step values must not make a pre-feature snapshot unreadable:
    /// all existing settings remain required, while only the new values use
    /// defaults when absent. Unknown retired keys such as `showInMenuBar` are
    /// deliberately ignored and not re-encoded.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            capsLockInputSourceSwitching: try values.decode(Bool.self, forKey: .capsLockInputSourceSwitching),
            reverseMouseWheelVertically: try values.decode(Bool.self, forKey: .reverseMouseWheelVertically),
            sideButtonNavigation: try values.decode(Bool.self, forKey: .sideButtonNavigation),
            launchAtLogin: try values.decode(Bool.self, forKey: .launchAtLogin),
            fixedMouseWheelStepEnabled: try values.decodeIfPresent(Bool.self, forKey: .fixedMouseWheelStepEnabled) ?? false,
            mouseWheelStepLines: try values.decodeIfPresent(Int.self, forKey: .mouseWheelStepLines) ?? Self.defaultMouseWheelStepLines
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(capsLockInputSourceSwitching, forKey: .capsLockInputSourceSwitching)
        try values.encode(reverseMouseWheelVertically, forKey: .reverseMouseWheelVertically)
        try values.encode(sideButtonNavigation, forKey: .sideButtonNavigation)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(fixedMouseWheelStepEnabled, forKey: .fixedMouseWheelStepEnabled)
        try values.encode(mouseWheelStepLines, forKey: .mouseWheelStepLines)
    }

    private static func normalizedMouseWheelStepLines(_ value: Int) -> Int {
        min(max(value, mouseWheelStepLineRange.lowerBound), mouseWheelStepLineRange.upperBound)
    }
}

enum TidyTapFeature: String, Codable, CaseIterable {
    case capsLock
    case mouseWheel
    case sideButtonNavigation
}

enum TidyTapPermission: String, Codable, CaseIterable {
    case accessibility
    case inputMonitoring
}

enum TidyTapPermissionState: String, Codable, Equatable {
    case unknown
    case authorized
    case denied
}

/// A UI-independent permission snapshot. The app can display this while the
/// helper uses the same requirements to reject unsafe feature activation.
struct TidyTapFeaturePermissionState: Codable, Equatable {
    var accessibility: TidyTapPermissionState
    var inputMonitoring: TidyTapPermissionState

    init(
        accessibility: TidyTapPermissionState = .unknown,
        inputMonitoring: TidyTapPermissionState = .unknown
    ) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    func requiredPermissions(for feature: TidyTapFeature) -> [TidyTapPermission] {
        switch feature {
        case .capsLock:
            []
        case .mouseWheel:
            [.accessibility, .inputMonitoring]
        case .sideButtonNavigation:
            [.accessibility]
        }
    }

    func isAuthorized(for feature: TidyTapFeature) -> Bool {
        requiredPermissions(for: feature).allSatisfy { permission in
            switch permission {
            case .accessibility:
                accessibility == .authorized
            case .inputMonitoring:
                inputMonitoring == .authorized
            }
        }
    }
}

enum TidyTapPermissionRequestKind: String, Codable, Equatable {
    case refresh
    case request
}

/// A single correlated permission command for the embedded helper. The app
/// persists it before launching the helper so a launch-time notification race
/// cannot lose an explicit user request.
struct TidyTapPermissionRequest: Codable, Equatable {
    let requestID: UUID
    let kind: TidyTapPermissionRequestKind
    let permission: TidyTapPermission?
}

struct TidyTapPermissionResult: Codable, Equatable {
    let requestID: UUID
    let state: TidyTapFeaturePermissionState
}

struct TidyTapSettingsRequest: Codable, Equatable {
    let settings: TidyTapSettings
    let applyRequestID: UUID
}

enum TidyTapApplyOutcome: String, Codable, Equatable {
    case pending
    case applied
    /// A requested input feature could not run because a required permission is
    /// unavailable, but an independent requested feature remains active.
    case partiallyApplied
    case failed
    case recoveryRequired
}

enum TidyTapApplyComponent: String, Codable, Equatable {
    case settings
    case capsLock
    case eventTap
    case menuBar
    case lifecycle
}

/// The single status value persisted after every apply attempt. Keeping this
/// as one Codable value prevents readers from observing a result ID and result
/// body from different transactions.
struct TidyTapApplyStatus: Codable, Equatable {
    let applyRequestID: UUID
    let outcome: TidyTapApplyOutcome
    let failedComponent: TidyTapApplyComponent?
    let errorCode: String?
    /// The exact state left active by this result. This is present for every
    /// terminal helper result so a restarted settings app never has to infer
    /// effective toggles from an error-code string.
    let effectiveSettings: TidyTapSettings?

    init(
        applyRequestID: UUID,
        outcome: TidyTapApplyOutcome,
        failedComponent: TidyTapApplyComponent?,
        errorCode: String?,
        effectiveSettings: TidyTapSettings? = nil
    ) {
        self.applyRequestID = applyRequestID
        self.outcome = outcome
        self.failedComponent = failedComponent
        self.errorCode = errorCode
        self.effectiveSettings = effectiveSettings
    }

    static func pending(_ requestID: UUID) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .pending,
            failedComponent: nil,
            errorCode: nil,
            effectiveSettings: nil
        )
    }

    static func applied(_ requestID: UUID) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .applied,
            failedComponent: nil,
            errorCode: nil,
            effectiveSettings: nil
        )
    }

    static func applied(_ requestID: UUID, effectiveSettings: TidyTapSettings) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .applied,
            failedComponent: nil,
            errorCode: nil,
            effectiveSettings: effectiveSettings
        )
    }
}

protocol TidyTapPreferencesStoring: AnyObject {
    func readRequest() -> TidyTapSettingsRequest
    func write(settings: TidyTapSettings, applyRequestID: UUID) throws
    func readApplyStatus() -> TidyTapApplyStatus?
    func writeApplyStatus(_ status: TidyTapApplyStatus) throws
    func readPermissionRequest() -> TidyTapPermissionRequest?
    func writePermissionRequest(_ request: TidyTapPermissionRequest) throws
    func readPermissionResult() -> TidyTapPermissionResult?
    func writePermissionResult(_ result: TidyTapPermissionResult) throws
}

/// Caps Lock changes system-owned values, so the helper persists the exact
/// engine ownership token in the same durable domain as the settings snapshot.
/// The token stays helper-private; the Dock app never interprets it.
protocol TidyTapCapsOwnershipStoring: AnyObject {
    func readCapsLockJournalData() -> Data?
    func writeCapsLockJournalData(_ data: Data?) throws
}

enum TidyTapPreferencesError: Error {
    case encodingFailed
}

/// Both processes explicitly use this suite rather than `UserDefaults.standard`
/// so they always address exactly one preferences domain.
final class TidyTapPreferencesStore: TidyTapPreferencesStoring, TidyTapCapsOwnershipStoring {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: TidyTapPreferences.domain) ?? .standard
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func readRequest() -> TidyTapSettingsRequest {
        synchronize()

        if let data = defaults.data(forKey: TidyTapPreferences.settingsKey),
           let request = try? decoder.decode(TidyTapSettingsRequest.self, from: data) {
            return request
        }

        let requestID = UUID(uuidString: defaults.string(forKey: TidyTapPreferences.applyRequestIDKey) ?? "") ?? UUID()
        return TidyTapSettingsRequest(settings: .defaults, applyRequestID: requestID)
    }

    func write(settings: TidyTapSettings, applyRequestID: UUID) throws {
        let request = TidyTapSettingsRequest(settings: settings, applyRequestID: applyRequestID)
        guard let data = try? encoder.encode(request) else {
            throw TidyTapPreferencesError.encodingFailed
        }

        defaults.set(data, forKey: TidyTapPreferences.settingsKey)
        defaults.set(applyRequestID.uuidString, forKey: TidyTapPreferences.applyRequestIDKey)
        defaults.set(try encode(TidyTapApplyStatus.pending(applyRequestID)), forKey: TidyTapPreferences.applyStatusKey)
        synchronize()
    }

    func readApplyStatus() -> TidyTapApplyStatus? {
        synchronize()
        guard let data = defaults.data(forKey: TidyTapPreferences.applyStatusKey) else {
            return nil
        }
        return try? decoder.decode(TidyTapApplyStatus.self, from: data)
    }

    func writeApplyStatus(_ status: TidyTapApplyStatus) throws {
        defaults.set(try encode(status), forKey: TidyTapPreferences.applyStatusKey)
        synchronize()
    }

    func readPermissionRequest() -> TidyTapPermissionRequest? {
        synchronize()
        guard let data = defaults.data(forKey: TidyTapPreferences.permissionRequestKey) else {
            return nil
        }
        return try? decoder.decode(TidyTapPermissionRequest.self, from: data)
    }

    func writePermissionRequest(_ request: TidyTapPermissionRequest) throws {
        defaults.set(try encode(request), forKey: TidyTapPreferences.permissionRequestKey)
        synchronize()
    }

    func readPermissionResult() -> TidyTapPermissionResult? {
        synchronize()
        guard let data = defaults.data(forKey: TidyTapPreferences.permissionResultKey) else {
            return nil
        }
        return try? decoder.decode(TidyTapPermissionResult.self, from: data)
    }

    func writePermissionResult(_ result: TidyTapPermissionResult) throws {
        defaults.set(try encode(result), forKey: TidyTapPreferences.permissionResultKey)
        synchronize()
    }

    func readCapsLockJournalData() -> Data? {
        synchronize()
        return defaults.data(forKey: TidyTapPreferences.capsLockOwnershipKey)
    }

    func writeCapsLockJournalData(_ data: Data?) throws {
        defaults.set(data, forKey: TidyTapPreferences.capsLockOwnershipKey)
        synchronize()
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        guard let data = try? encoder.encode(value) else {
            throw TidyTapPreferencesError.encodingFailed
        }
        return data
    }

    private func synchronize() {
        defaults.synchronize()
    }
}

enum TidyTapPreferences {
    static let domain = "com.sharknia.TidyTap"
    static let settingsKey = "settings"
    static let applyRequestIDKey = "applyRequestID"
    static let applyStatusKey = "applyStatus"
    static let capsLockOwnershipKey = "capsLockOwnership"
    static let permissionRequestKey = "permissionRequest"
    static let permissionResultKey = "permissionResult"
}
