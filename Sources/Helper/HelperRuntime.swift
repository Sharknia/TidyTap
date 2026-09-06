import AppKit
import TidyTapInputEngine

/// A background-only helper. It owns the process lifetime and applies the
/// complete persisted snapshot at launch and after each change notification.
@MainActor
final class HelperRuntime {
    private var lifecycle: HelperLifecycle?
    private let launchSmoke = TidyTapLaunchSmoke.current()

    func start() {
        let preferences: TidyTapPreferencesStore
        let capsFeature: TidyTapCapsFeatureApplying
        let inputFeatures: TidyTapInputFeaturesApplying
        let menuBar: TidyTapMenuBarApplying

        if let launchSmoke {
            preferences = TidyTapPreferencesStore(defaults: launchSmoke.makePreferences())
            capsFeature = LaunchSmokeCapsFeature(smoke: launchSmoke)
            inputFeatures = LaunchSmokeInputFeatures(smoke: launchSmoke)
            menuBar = LaunchSmokeMenuBar(smoke: launchSmoke)
        } else {
            preferences = TidyTapPreferencesStore()
            capsFeature = CapsLockFeatureAdapter(
                system: MacOSSystemApplyAdapter(),
                ownershipStore: preferences
            )
            inputFeatures = InputFeaturesAdapter()
            menuBar = MenuBarController()
        }

        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: capsFeature,
            inputFeatures: inputFeatures,
            menuBar: menuBar,
            terminator: ApplicationTerminator()
        )
        if let productionInputFeatures = inputFeatures as? InputFeaturesAdapter {
            productionInputFeatures.runtimeStatusHandler = { [weak coordinator] requestID, result, error in
                DispatchQueue.main.async {
                    coordinator?.reportRuntimeInput(requestID: requestID, result, error: error)
                }
            }
        }
        let lifecycle = HelperLifecycle(
            coordinator: coordinator,
            permissionCoordinator: HelperPermissionCoordinator(preferences: preferences)
        )
        self.lifecycle = lifecycle
        lifecycle.start()
        launchSmoke?.report("helper-delegate-started")
    }

    func stop() {
        lifecycle?.stop()
    }
}

private final class LaunchSmokeCapsFeature: TidyTapCapsFeatureApplying {
    private let smoke: TidyTapLaunchSmoke
    private var enabled = false

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func apply(capsLockEnabled: Bool) throws {
        enabled = capsLockEnabled
        smoke.report("helper-caps-\(capsLockEnabled ? "enabled" : "disabled")")
    }

    func currentCapsLockEnabled() throws -> Bool {
        enabled
    }
}

private final class LaunchSmokeInputFeatures: TidyTapInputFeaturesApplying {
    private let smoke: TidyTapLaunchSmoke

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        requestID: UUID
    ) throws -> TidyTapInputFeatureApplyResult {
        smoke.report(
            "helper-input-\(reverseMouseWheel ? "wheel-on" : "wheel-off")-" +
                "\(sideButtonNavigation ? "buttons-on" : "buttons-off")"
        )
        return .applied
    }

    func forcePassThrough() throws {}

    func currentConfiguration() -> TidyTapInputFeatureConfiguration {
        .disabled
    }
}

@MainActor
private final class LaunchSmokeMenuBar: TidyTapMenuBarApplying {
    private let smoke: TidyTapLaunchSmoke
    private(set) var isMenuBarVisible = false

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func applyMenuBar(visible: Bool) throws {
        isMenuBarVisible = visible
        smoke.report("helper-menu-\(visible ? "visible" : "hidden")")
    }
}
