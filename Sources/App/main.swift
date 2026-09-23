import AppKit

let application = NSApplication.shared
let initialFinderFeedback = TidyTapIPC.finderFeedback(in: ProcessInfo.processInfo.environment)
if initialFinderFeedback != nil ||
    ProcessInfo.processInfo.environment[TidyTapIPC.clipboardHistoryModeEnvironmentKey] == "1" {
    application.setActivationPolicy(.accessory)
}
let applicationDelegate = AppDelegate(
    initialFinderFeedback: initialFinderFeedback
)
application.delegate = applicationDelegate
withExtendedLifetime(applicationDelegate) {
    application.run()
}
