import AppKit
import Darwin

#if DEBUG
let developmentRun = true
#else
let developmentRun = TidyTapLaunchSmoke.current() != nil
#endif

guard TidyTapProduct.isInstalledCopy(Bundle.main.bundleURL, allowDevelopment: developmentRun) else {
    _ = NSApplication.shared
    let alert = NSAlert()
    alert.messageText = String(localized: "Open the installed TidyTap")
    alert.informativeText = String(localized: "Move TidyTap to Applications and open it from there.")
    alert.runModal()
    exit(1)
}

let launchSmoke = TidyTapLaunchSmoke.current()
let appLockURL = TidyTapProduct.appLockURL(
    preferencesSuite: launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
)
try FileManager.default.createDirectory(
    at: appLockURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
let appLockDescriptor = open(appLockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
guard appLockDescriptor >= 0 else { exit(1) }
guard flock(appLockDescriptor, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

if launchSmoke == nil {
    if NSRunningApplication.runningApplications(withBundleIdentifier: TidyTapProduct.appBundleIdentifier)
        .contains(where: { $0.processIdentifier != getpid() }) {
        let environment = ProcessInfo.processInfo.environment
        if environment[TidyTapProduct.backgroundUpdateEnvironmentKey] != "1" &&
            environment[TidyTapIPC.clipboardHistoryModeEnvironmentKey] != "1" &&
            TidyTapIPC.finderFeedback(in: environment) == nil {
            _ = NSApplication.shared
            let alert = NSAlert()
            alert.messageText = String(localized: "Another TidyTap is running")
            alert.informativeText = String(localized: "Quit the other copy, then open TidyTap again.")
            alert.runModal()
        }
        exit(0)
    }
}

let application = NSApplication.shared
let initialFinderFeedback = TidyTapIPC.finderFeedback(in: ProcessInfo.processInfo.environment)
if initialFinderFeedback != nil ||
    ProcessInfo.processInfo.environment[TidyTapIPC.clipboardHistoryModeEnvironmentKey] == "1" ||
    ProcessInfo.processInfo.environment[TidyTapProduct.backgroundUpdateEnvironmentKey] == "1" {
    application.setActivationPolicy(.accessory)
}
let applicationDelegate = AppDelegate(
    initialFinderFeedback: initialFinderFeedback
)
application.delegate = applicationDelegate
withExtendedLifetime(applicationDelegate) {
    application.run()
}
