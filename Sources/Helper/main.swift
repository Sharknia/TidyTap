import AppKit

// Wait for any independently launched 0.0.2 app to release its event taps.
if TidyTapLaunchSmoke.current() == nil {
    let legacyApps = NSRunningApplication.runningApplications(
        withBundleIdentifier: TidyTapProduct.helperBundleIdentifier
    ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    for legacy in legacyApps { legacy.terminate() }
    let deadline = Date().addingTimeInterval(2)
    while legacyApps.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard legacyApps.allSatisfy(\.isTerminated) else { exit(1) }
}

// Manual launches and ServiceManagement may race. The kernel releases this
// lock on every exit/crash, so no stale PID or distributed election is needed.
let suite = TidyTapLaunchSmoke.current()?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
let lockDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(suite, isDirectory: true)
try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
let lockDescriptor = open(lockDirectory.appendingPathComponent("worker.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
guard lockDescriptor >= 0 else { exit(1) }
guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

// Do not create NSApplication: registering a second app instance would make
// LaunchServices route subsequent settings launches to this invisible worker.
let runtime = HelperRuntime()
withExtendedLifetime(runtime) {
    runtime.start()
    CFRunLoopRun()
    runtime.stop()
}
