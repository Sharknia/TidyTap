import Darwin
import AppKit
import Foundation
import Security

enum HelperLauncherError: Error, Equatable {
    case invalidApplicationBundle
    case invalidHelperCode(OSStatus)
    case workerInspectionFailed
    case workerIdentityCouldNotBeVerified(pid_t, OSStatus)
    case workerDidNotBecomeReady
    case workerTerminationFailed(pid_t, Int32)
}

enum TidyTapWorkerCodeState: Equatable {
    case current
    case stale
    case gone
    case unverifiable(OSStatus)
}

enum TidyTapWorkerLockState: Equatable {
    case free(lastOwner: TidyTapWorkerLockOwner?)
    case held(owner: TidyTapWorkerLockOwner?)
}

protocol TidyTapWorkerRuntime: AnyObject {
    func prepare() throws
    func inspectLock() throws -> TidyTapWorkerLockState
    func inspectProcess(_ owner: TidyTapWorkerLockOwner) -> TidyTapWorkerCodeState
    func workersAtExpectedPath() throws -> [(TidyTapWorkerLockOwner, TidyTapWorkerCodeState)]
    func legacyWorkers() throws -> [TidyTapWorkerLockOwner]
    func launch(nonce: UUID) throws
    func terminate(_ owner: TidyTapWorkerLockOwner) throws
    func terminateLegacy(_ owner: TidyTapWorkerLockOwner) throws
    func pause()
}

final class HelperLauncher: TidyTapHelperLaunching {
    private let runtime: TidyTapWorkerRuntime
    private let maximumAttempts: Int
    private let maximumLaunches: Int

    convenience init() {
        self.init(runtime: SystemTidyTapWorkerRuntime(), maximumAttempts: 60, maximumLaunches: 3)
    }

    init(runtime: TidyTapWorkerRuntime, maximumAttempts: Int, maximumLaunches: Int) {
        self.runtime = runtime
        self.maximumAttempts = maximumAttempts
        self.maximumLaunches = maximumLaunches
    }

    func ensureHelperRunning() throws {
        try runtime.prepare()
        let launchNonce = UUID()
        var launches = 0
        var attemptsAfterLaunch = maximumAttempts
        var signaled = Set<TidyTapWorkerLockOwner.ProcessIdentity>()
        var signaledLegacy = Set<TidyTapWorkerLockOwner.ProcessIdentity>()

        for _ in 0..<maximumAttempts {
            let legacyWorkers = try runtime.legacyWorkers()
            if !legacyWorkers.isEmpty {
                for legacy in legacyWorkers
                    where signaledLegacy.insert(legacy.processIdentity).inserted {
                    try runtime.terminateLegacy(legacy)
                }
                runtime.pause()
                continue
            }

            switch try runtime.inspectLock() {
            case .free(let lastOwner):
                if lastOwner?.readiness == .acknowledged,
                   lastOwner?.launchNonce == launchNonce {
                    return
                }
                if launches < maximumLaunches, attemptsAfterLaunch >= 3 {
                    try runtime.launch(nonce: launchNonce)
                    launches += 1
                    attemptsAfterLaunch = 0
                }

            case .held(let owner):
                if let owner {
                    switch runtime.inspectProcess(owner) {
                    case .current:
                        if owner.readiness == .acknowledged {
                            return
                        }
                    case .stale:
                        try terminateOnce(owner, signaled: &signaled)
                    case .gone:
                        break
                    case .unverifiable(let status):
                        throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                            owner.processIdentifier,
                            status
                        )
                    }
                }

                let candidates = try runtime.workersAtExpectedPath()
                for (candidate, state) in candidates {
                    switch state {
                    case .stale:
                        try terminateOnce(candidate, signaled: &signaled)
                    case .current, .gone:
                        break
                    case .unverifiable(let status):
                        throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                            candidate.processIdentifier,
                            status
                        )
                    }
                }
            }

            runtime.pause()
            attemptsAfterLaunch += 1
        }

        throw HelperLauncherError.workerDidNotBecomeReady
    }

    private func terminateOnce(
        _ owner: TidyTapWorkerLockOwner,
        signaled: inout Set<TidyTapWorkerLockOwner.ProcessIdentity>
    ) throws {
        guard signaled.insert(owner.processIdentity).inserted else { return }
        try runtime.terminate(owner)
    }
}

final class SystemTidyTapWorkerRuntime: TidyTapWorkerRuntime {
    private let expectedExecutableURL: URL
    private let expectedLegacyBundleURL: URL
    private let expectedLegacyExecutableURL: URL
    private let lockURL: URL
    private let expectedUID: uid_t
    private let applicationBundleIsValid: () -> Bool
    private let additionalLaunchEnvironment: [String: String]
    private let registeredLegacyProcessIdentifiers: () -> [pid_t]

    convenience init(
        bundle: Bundle = .main,
        expectedUID: uid_t = getuid()
    ) {
        let expectedExecutableURL = bundle.bundleURL
            .appendingPathComponent(TidyTapProduct.helperExecutablePath)
        self.init(
            expectedExecutableURL: expectedExecutableURL,
            applicationBundleURL: bundle.bundleURL,
            lockURL: TidyTapProduct.workerLockURL(),
            expectedUID: expectedUID,
            additionalLaunchEnvironment: [:],
            applicationBundleIsValid: {
                bundle.bundleIdentifier == TidyTapProduct.appBundleIdentifier
            }
        )
    }

    init(
        expectedExecutableURL: URL,
        applicationBundleURL: URL? = nil,
        lockURL: URL,
        expectedUID: uid_t,
        additionalLaunchEnvironment: [String: String] = [:],
        registeredLegacyProcessIdentifiers: @escaping () -> [pid_t] = {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: TidyTapProduct.helperBundleIdentifier
            ).map(\.processIdentifier)
        },
        applicationBundleIsValid: @escaping () -> Bool
    ) {
        self.expectedExecutableURL = expectedExecutableURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let derivedApplicationBundleURL = expectedExecutableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let applicationBundleURL = applicationBundleURL ?? derivedApplicationBundleURL
        expectedLegacyBundleURL = applicationBundleURL
            .appendingPathComponent(TidyTapProduct.legacyHelperBundlePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        expectedLegacyExecutableURL = applicationBundleURL
            .appendingPathComponent(TidyTapProduct.legacyHelperExecutablePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.lockURL = lockURL
        self.expectedUID = expectedUID
        self.additionalLaunchEnvironment = additionalLaunchEnvironment
        self.registeredLegacyProcessIdentifiers = registeredLegacyProcessIdentifiers
        self.applicationBundleIsValid = applicationBundleIsValid
    }

    func prepare() throws {
        guard applicationBundleIsValid(),
              expectedExecutableURL.path.hasSuffix("/\(TidyTapProduct.helperExecutablePath)"),
              FileManager.default.isExecutableFile(atPath: expectedExecutableURL.path) else {
            throw HelperLauncherError.invalidApplicationBundle
        }

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(
            expectedExecutableURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard status == errSecSuccess, let staticCode else {
            throw HelperLauncherError.invalidHelperCode(status)
        }
        status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        guard status == errSecSuccess else {
            throw HelperLauncherError.invalidHelperCode(status)
        }
    }

    func inspectLock() throws -> TidyTapWorkerLockState {
        let directory = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw HelperLauncherError.workerInspectionFailed }
        defer { close(descriptor) }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            let lastOwner = try readLockOwner(from: descriptor)
            flock(descriptor, LOCK_UN)
            return .free(lastOwner: lastOwner)
        }
        guard errno == EWOULDBLOCK else {
            throw HelperLauncherError.workerInspectionFailed
        }

        return .held(owner: try readLockOwner(from: descriptor))
    }

    private func readLockOwner(from descriptor: Int32) throws -> TidyTapWorkerLockOwner? {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw HelperLauncherError.workerInspectionFailed
        }
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = bytes.withUnsafeMutableBytes { buffer in
            read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count >= 0 else { throw HelperLauncherError.workerInspectionFailed }
        return TidyTapWorkerLockOwner(encoded: Data(bytes.prefix(count)))
    }

    func inspectProcess(_ owner: TidyTapWorkerLockOwner) -> TidyTapWorkerCodeState {
        guard let current = TidyTapWorkerLockOwner.process(
            processIdentifier: owner.processIdentifier
        ), current.processIdentity == owner.processIdentity else {
            return .gone
        }
        guard processUID(owner.processIdentifier) == expectedUID,
              processPath(owner.processIdentifier) == expectedExecutableURL.path else {
            return .gone
        }

        var code: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: owner.processIdentifier)
        ] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard copyStatus == errSecSuccess, let code else {
            return copyStatus == errSecCSNoSuchCode ? .gone : .unverifiable(copyStatus)
        }

        let validity = SecCodeCheckValidity(code, SecCSFlags(), nil)
        switch validity {
        case errSecSuccess:
            return .current
        case errSecCSStaticCodeChanged:
            // This is Security.framework's specific evidence that the code
            // mapped in this PID is not the code now present at the same path.
            return .stale
        case errSecCSNoSuchCode:
            return .gone
        default:
            return .unverifiable(validity)
        }
    }

    func workersAtExpectedPath() throws -> [(TidyTapWorkerLockOwner, TidyTapWorkerCodeState)] {
        try processOwners(at: expectedExecutableURL.path).map { owner in
            (owner, inspectProcess(owner))
        }
    }

    func legacyWorkers() throws -> [TidyTapWorkerLockOwner] {
        // A pre-lock worker in another installation can still intercept input.
        // Do not terminate outside this app's verified migration path, but do
        // not start a second worker alongside that other copy either.
        for processIdentifier in registeredLegacyProcessIdentifiers() {
            guard processIdentifier > 0,
                  processUID(processIdentifier) == expectedUID,
                  let owner = TidyTapWorkerLockOwner.process(processIdentifier: processIdentifier) else {
                continue
            }
            if processPath(processIdentifier) != expectedLegacyExecutableURL.path,
               TidyTapWorkerLockOwner.process(processIdentifier: processIdentifier)?.processIdentity
                    == owner.processIdentity {
                throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                    processIdentifier,
                    errSecCSReqFailed
                )
            }
        }
        var validated = [TidyTapWorkerLockOwner]()
        for owner in try processOwners(at: expectedLegacyExecutableURL.path) {
            if try validatedLegacyApplication(owner) != nil {
                validated.append(owner)
            }
        }
        return validated
    }

    private func processOwners(at executablePath: String) throws -> [TidyTapWorkerLockOwner] {
        let capacity = max(proc_listallpids(nil, 0), 64)
        var processIdentifiers = [pid_t](repeating: 0, count: Int(capacity))
        let count = processIdentifiers.withUnsafeMutableBytes { bytes in
            proc_listallpids(bytes.baseAddress, Int32(bytes.count))
        }
        guard count >= 0 else { throw HelperLauncherError.workerInspectionFailed }

        return processIdentifiers.prefix(Int(count)).compactMap { processIdentifier in
            guard processIdentifier > 0,
                  processIdentifier != getpid(),
                  processUID(processIdentifier) == expectedUID,
                  processPath(processIdentifier) == executablePath,
                  let owner = TidyTapWorkerLockOwner.process(processIdentifier: processIdentifier) else {
                return nil
            }
            return owner
        }
    }

    func launch(nonce: UUID) throws {
        let process = Process()
        process.executableURL = expectedExecutableURL
        process.environment = ProcessInfo.processInfo.environment
            .merging(additionalLaunchEnvironment) { _, value in value }
            .merging([
                TidyTapProduct.workerLaunchNonceEnvironmentKey: nonce.uuidString
            ]) { _, value in value }
        try process.run()
    }

    func terminate(_ owner: TidyTapWorkerLockOwner) throws {
        switch inspectProcess(owner) {
        case .gone:
            return
        case .stale:
            break
        case .current:
            throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                owner.processIdentifier,
                errSecCSReqFailed
            )
        case .unverifiable(let status):
            throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                owner.processIdentifier,
                status
            )
        }
        guard kill(owner.processIdentifier, SIGTERM) == 0 || errno == ESRCH else {
            throw HelperLauncherError.workerTerminationFailed(owner.processIdentifier, errno)
        }
    }

    func terminateLegacy(_ owner: TidyTapWorkerLockOwner) throws {
        guard let application = try validatedLegacyApplication(owner) else { return }
        guard application.terminate() else {
            throw HelperLauncherError.workerTerminationFailed(owner.processIdentifier, EPERM)
        }
    }

    func pause() {
        usleep(50_000)
    }

    private func processUID(_ processIdentifier: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let actualSize = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(expectedSize)
        )
        return actualSize == expectedSize ? info.pbi_uid : nil
    }

    private func validatedLegacyApplication(
        _ owner: TidyTapWorkerLockOwner
    ) throws -> NSRunningApplication? {
        guard let current = TidyTapWorkerLockOwner.process(
            processIdentifier: owner.processIdentifier
        ), current.processIdentity == owner.processIdentity else {
            return nil
        }
        guard processUID(owner.processIdentifier) == expectedUID,
              processPath(owner.processIdentifier) == expectedLegacyExecutableURL.path,
              let application = NSRunningApplication(processIdentifier: owner.processIdentifier),
              application.bundleIdentifier == TidyTapProduct.helperBundleIdentifier,
              application.bundleURL.map(canonicalPath) == expectedLegacyBundleURL.path,
              application.executableURL.map(canonicalPath) == expectedLegacyExecutableURL.path else {
            throw HelperLauncherError.workerIdentityCouldNotBeVerified(
                owner.processIdentifier,
                errSecCSReqFailed
            )
        }
        return application
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func processPath(_ processIdentifier: pid_t) -> String? {
        // `PROC_PIDPATHINFO_MAXSIZE` is not imported into Swift. Darwin defines
        // it as four MAXPATHLEN buffers.
        var buffer = [CChar](repeating: 0, count: 4 * 1_024)
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
