import Darwin
import Foundation

func writeLockOwner(_ owner: TidyTapWorkerLockOwner, to descriptor: Int32) -> Bool {
    let data = owner.encoded
    return ftruncate(descriptor, 0) == 0 &&
        data.withUnsafeBytes { bytes in
            pwrite(descriptor, bytes.baseAddress, bytes.count, 0)
        } == data.count &&
        fsync(descriptor) == 0
}

// Manual launches and ServiceManagement may race. The kernel releases this
// lock on every exit/crash, so no stale PID or distributed election is needed.
let suite = TidyTapLaunchSmoke.current()?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
let lockURL = TidyTapProduct.workerLockURL(preferencesSuite: suite)
let lockDirectory = lockURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
guard lockDescriptor >= 0 else { exit(1) }
guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
let launchNonce = ProcessInfo.processInfo.environment[TidyTapProduct.workerLaunchNonceEnvironmentKey]
    .flatMap(UUID.init(uuidString:))
guard let processOwner = TidyTapWorkerLockOwner.current(),
      writeLockOwner(
          processOwner.recording(readiness: .starting, launchNonce: launchNonce),
          to: lockDescriptor
      ) else { exit(1) }

// Do not create NSApplication: registering a second app instance would make
// LaunchServices route subsequent settings launches to this invisible worker.
let runtime = HelperRuntime()
withExtendedLifetime(runtime) {
    runtime.start()
    guard writeLockOwner(
        processOwner.recording(readiness: .acknowledged, launchNonce: launchNonce),
        to: lockDescriptor
    ) else {
        runtime.stop()
        exit(1)
    }
    CFRunLoopRun()
    runtime.stop()
}
