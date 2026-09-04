import Foundation

/// The complete user-configurable state for the 0.1.0 preferences domain.
struct TidyTapSettings: Codable, Equatable {
    var capsLockInputSourceSwitching: Bool
    var reverseMouseWheelVertically: Bool
    var sideButtonNavigation: Bool
    var launchAtLogin: Bool
    var showInMenuBar: Bool

    static let defaults = TidyTapSettings(
        capsLockInputSourceSwitching: false,
        reverseMouseWheelVertically: false,
        sideButtonNavigation: false,
        launchAtLogin: false,
        showInMenuBar: false
    )

    /// The login-item preference alone must not keep a helper process alive.
    var requiresHelper: Bool {
        capsLockInputSourceSwitching ||
            reverseMouseWheelVertically ||
            sideButtonNavigation ||
            showInMenuBar
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
}
