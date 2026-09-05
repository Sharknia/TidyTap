import Foundation

/// Opt-in launch-smoke configuration used only by the repository's isolated
/// process-level smoke test. Production launches never set these variables.
struct TidyTapLaunchSmoke {
    static let enabledKey = "TIDYTAP_LAUNCH_SMOKE"
    static let preferencesSuiteKey = "TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE"
    static let suitePrefix = "com.sharknia.TidyTap.LaunchSmoke."

    let preferencesSuite: String

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TidyTapLaunchSmoke? {
        guard environment[enabledKey] == "1",
              let suite = environment[preferencesSuiteKey],
              suite.hasPrefix(suitePrefix),
              suite.count > suitePrefix.count else {
            return nil
        }
        return TidyTapLaunchSmoke(preferencesSuite: suite)
    }

    func makePreferences() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: preferencesSuite) else {
            preconditionFailure("Could not create isolated launch-smoke preferences")
        }
        return defaults
    }

    func report(_ event: String) {
        let line = "TIDYTAP_LAUNCH_SMOKE \(event)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
