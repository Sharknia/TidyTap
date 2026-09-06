import Darwin
import Foundation
import Security
import XCTest

final class HelperLauncherTests: XCTestCase {
    private let stale = TidyTapWorkerLockOwner(
        processIdentifier: 101,
        startSeconds: 10,
        startMicroseconds: 20
    )
    private let current = TidyTapWorkerLockOwner(
        processIdentifier: 202,
        startSeconds: 30,
        startMicroseconds: 40,
        readiness: .acknowledged
    )

    func testLockOwnerRecordRoundTripsAndRejectsUnversionedData() {
        XCTAssertEqual(TidyTapWorkerLockOwner(encoded: current.encoded), current)
        XCTAssertNil(TidyTapWorkerLockOwner(encoded: Data("202 30 40\n".utf8)))
    }

    func testAlreadyReadyCurrentWorkerDoesNotLaunchOrTerminate() throws {
        let runtime = FakeWorkerRuntime(
            lockStates: [.held(owner: current)],
            processStates: [current: .current]
        )

        try makeLauncher(runtime).ensureHelperRunning()

        XCTAssertEqual(runtime.launchCount, 0)
        XCTAssertEqual(runtime.terminated, [])
    }

    func testLaunchWaitsForLockOwnerReadiness() throws {
        let runtime = FakeWorkerRuntime(
            lockStates: [
                .free(lastOwner: nil),
                .free(lastOwner: nil),
                .held(owner: current)
            ],
            processStates: [current: .current]
        )

        try makeLauncher(runtime).ensureHelperRunning()

        XCTAssertEqual(runtime.launchCount, 1)
        XCTAssertEqual(runtime.pauseCount, 2)
    }

    func testStaleExactWorkerIsTerminatedOnceThenReplaced() throws {
        let runtime = FakeWorkerRuntime(
            lockStates: [
                .held(owner: stale),
                .free(lastOwner: nil),
                .held(owner: current)
            ],
            processStates: [stale: .stale, current: .current]
        )

        try makeLauncher(runtime).ensureHelperRunning()

        XCTAssertEqual(runtime.terminated, [stale])
        XCTAssertEqual(runtime.launchCount, 1)
    }

    func testLegacyEmptyLockRecordUsesOnlyInspectedExactPathCandidate() throws {
        let runtime = FakeWorkerRuntime(
            lockStates: [
                .held(owner: nil),
                .free(lastOwner: nil),
                .held(owner: current)
            ],
            processStates: [current: .current],
            pathCandidates: [(stale, .stale)]
        )
        runtime.clearCandidatesAfterTermination = true

        try makeLauncher(runtime).ensureHelperRunning()

        XCTAssertEqual(runtime.terminated, [stale])
        XCTAssertEqual(runtime.launchCount, 1)
    }

    func testUnverifiableWorkerFailsClosedWithoutSignalOrLaunch() {
        let status = OSStatus(-9_999)
        let runtime = FakeWorkerRuntime(
            lockStates: [.held(owner: stale)],
            processStates: [stale: .unverifiable(status)]
        )

        XCTAssertThrowsError(try makeLauncher(runtime).ensureHelperRunning()) { error in
            XCTAssertEqual(
                error as? HelperLauncherError,
                .workerIdentityCouldNotBeVerified(stale.processIdentifier, status)
            )
        }
        XCTAssertEqual(runtime.terminated, [])
        XCTAssertEqual(runtime.launchCount, 0)
    }

    func testStaleWorkerThatDoesNotExitTimesOutWithoutRepeatedSignals() {
        let runtime = FakeWorkerRuntime(
            lockStates: [.held(owner: stale)],
            processStates: [stale: .stale]
        )

        XCTAssertThrowsError(try makeLauncher(runtime, attempts: 4).ensureHelperRunning()) { error in
            XCTAssertEqual(error as? HelperLauncherError, .workerDidNotBecomeReady)
        }
        XCTAssertEqual(runtime.terminated, [stale])
        XCTAssertEqual(runtime.launchCount, 0)
    }

    func testHeldUnknownLockTimesOutWithoutKillingUnrelatedProcess() {
        let runtime = FakeWorkerRuntime(lockStates: [.held(owner: nil)])

        XCTAssertThrowsError(try makeLauncher(runtime, attempts: 3).ensureHelperRunning()) { error in
            XCTAssertEqual(error as? HelperLauncherError, .workerDidNotBecomeReady)
        }
        XCTAssertEqual(runtime.terminated, [])
        XCTAssertEqual(runtime.launchCount, 0)
    }

    func testFastSuccessfulWorkerExitUsesMatchingAcknowledgement() throws {
        let runtime = FakeWorkerRuntime(lockStates: [.free(lastOwner: nil)])
        runtime.acknowledgeAndExitOnLaunch = true

        try makeLauncher(runtime, attempts: 4).ensureHelperRunning()

        XCTAssertEqual(runtime.launchCount, 1)
        XCTAssertEqual(runtime.pauseCount, 1)
    }

    func testExitWithoutAcknowledgementIsNeverSuccess() {
        let runtime = FakeWorkerRuntime(lockStates: [.free(lastOwner: nil)])

        XCTAssertThrowsError(try makeLauncher(runtime, attempts: 5).ensureHelperRunning()) { error in
            XCTAssertEqual(error as? HelperLauncherError, .workerDidNotBecomeReady)
        }
        XCTAssertEqual(runtime.launchCount, 2)
    }

    func testActualAllOffWorkerAcknowledgesBeforeFastExit() throws {
        let fileManager = FileManager.default
        let fixtureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TidyTapWorkerAllOff-\(UUID().uuidString)", isDirectory: true)
        let fixtureURL = fixtureDirectory
            .appendingPathComponent("TidyTap.app")
            .appendingPathComponent(TidyTapProduct.helperExecutablePath)
        try fileManager.createDirectory(
            at: fixtureURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: fixtureDirectory) }
        try fileManager.copyItem(at: builtHelperURL(), to: fixtureURL)
        try codesign(
            fixtureURL,
            requirement: "=designated => identifier \"\(TidyTapProduct.helperBundleIdentifier)\"",
            hardenedRuntime: false
        )

        let suite = TidyTapLaunchSmoke.suitePrefix + UUID().uuidString
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated worker preferences")
        }
        let requestID = UUID()
        try TidyTapPreferencesStore(defaults: defaults).write(
            settings: .defaults,
            applyRequestID: requestID
        )

        let runtime = SystemTidyTapWorkerRuntime(
            expectedExecutableURL: fixtureURL,
            lockURL: TidyTapProduct.workerLockURL(preferencesSuite: suite),
            expectedUID: getuid(),
            additionalLaunchEnvironment: [
                TidyTapLaunchSmoke.enabledKey: "1",
                TidyTapLaunchSmoke.preferencesSuiteKey: suite
            ],
            applicationBundleIsValid: { true }
        )

        try HelperLauncher(
            runtime: runtime,
            maximumAttempts: 100,
            maximumLaunches: 2
        ).ensureHelperRunning()

        let status = TidyTapPreferencesStore(defaults: defaults).readApplyStatus()
        XCTAssertEqual(status?.applyRequestID, requestID)
        XCTAssertEqual(status?.outcome, .applied)
        let lastOwner = try waitForFreeAcknowledgement(runtime: runtime)
        XCTAssertEqual(lastOwner.readiness, .acknowledged)
        XCTAssertNotNil(lastOwner.launchNonce)
        XCTAssertEqual(runtime.inspectProcess(lastOwner), .gone)
    }

    func testDynamicIdentityDetectsReplacementWhenDesignatedRequirementMatches() throws {
        try assertDynamicIdentityDetectsSamePathReplacement(
            explicitRequirement: "=designated => identifier \"\(TidyTapProduct.helperBundleIdentifier)\"",
            designatedRequirementsShouldMatch: true
        )
    }

    func testDynamicIdentityDetectsReplacementWhenAdHocDesignatedRequirementChanges() throws {
        try assertDynamicIdentityDetectsSamePathReplacement(
            explicitRequirement: nil,
            designatedRequirementsShouldMatch: false
        )
    }

    private func assertDynamicIdentityDetectsSamePathReplacement(
        explicitRequirement: String?,
        designatedRequirementsShouldMatch: Bool
    ) throws {
        let fileManager = FileManager.default
        let builtHelperURL = builtHelperURL()
        XCTAssertTrue(fileManager.isExecutableFile(atPath: builtHelperURL.path))

        let fixtureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TidyTapWorkerReplacement-\(UUID().uuidString)", isDirectory: true)
        let fixtureURL = fixtureDirectory
            .appendingPathComponent("TidyTap.app")
            .appendingPathComponent(TidyTapProduct.helperExecutablePath)
        let replacementURL = fixtureURL.deletingLastPathComponent()
            .appendingPathComponent("TidyTapHelper.next")
        try fileManager.createDirectory(
            at: fixtureURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: fixtureDirectory) }
        try fileManager.copyItem(at: builtHelperURL, to: fixtureURL)
        try fileManager.copyItem(at: builtHelperURL, to: replacementURL)

        try codesign(fixtureURL, requirement: explicitRequirement, hardenedRuntime: false)
        try codesign(replacementURL, requirement: explicitRequirement, hardenedRuntime: true)
        let oldHash = try codeHash(at: fixtureURL)
        let replacementHash = try codeHash(at: replacementURL)
        XCTAssertNotEqual(oldHash, replacementHash)
        let oldRequirement = try designatedRequirement(at: fixtureURL)
        let replacementRequirement = try designatedRequirement(at: replacementURL)
        if designatedRequirementsShouldMatch {
            XCTAssertEqual(oldRequirement, replacementRequirement)
        } else {
            XCTAssertNotEqual(oldRequirement, replacementRequirement)
        }

        let suite = TidyTapLaunchSmoke.suitePrefix + UUID().uuidString
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated worker preferences")
        }
        let preferences = TidyTapPreferencesStore(defaults: defaults)
        try preferences.write(
            settings: TidyTapSettings(
                capsLockInputSourceSwitching: true,
                reverseMouseWheelVertically: false,
                sideButtonNavigation: false,
                launchAtLogin: false
            ),
            applyRequestID: UUID()
        )

        let lockURL = TidyTapProduct.workerLockURL(preferencesSuite: suite)
        let runtime = SystemTidyTapWorkerRuntime(
            expectedExecutableURL: fixtureURL,
            lockURL: lockURL,
            expectedUID: getuid(),
            additionalLaunchEnvironment: [
                TidyTapLaunchSmoke.enabledKey: "1",
                TidyTapLaunchSmoke.preferencesSuiteKey: suite
            ],
            applicationBundleIsValid: { true }
        )
        try runtime.prepare()

        let process = Process()
        process.executableURL = fixtureURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            TidyTapLaunchSmoke.enabledKey: "1",
            TidyTapLaunchSmoke.preferencesSuiteKey: suite
        ]) { _, fixtureValue in fixtureValue }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let owner = try waitForLockOwner(runtime: runtime, process: process)
        XCTAssertEqual(owner.processIdentifier, process.processIdentifier)
        XCTAssertEqual(runtime.inspectProcess(owner), .current)
        XCTAssertEqual(processPath(process.processIdentifier), fixtureURL.path)

        guard rename(replacementURL.path, fixtureURL.path) == 0 else {
            throw HelperLauncherTestError.commandFailed("rename")
        }
        try runtime.prepare()
        XCTAssertTrue(process.isRunning)
        XCTAssertEqual(processPath(process.processIdentifier), fixtureURL.path)
        XCTAssertEqual(runtime.inspectProcess(owner), .stale)
        let discovered = try runtime.workersAtExpectedPath()
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.0.processIdentity, owner.processIdentity)
        XCTAssertEqual(discovered.first?.1, .stale)

        let replacementRequestID = UUID()
        try preferences.write(settings: .defaults, applyRequestID: replacementRequestID)
        try HelperLauncher(
            runtime: runtime,
            maximumAttempts: 100,
            maximumLaunches: 2
        ).ensureHelperRunning()

        try waitForProcessExit(process)
        XCTAssertEqual(preferences.readApplyStatus()?.applyRequestID, replacementRequestID)
        XCTAssertEqual(preferences.readApplyStatus()?.outcome, .applied)
        let replacementOwner = try waitForFreeAcknowledgement(runtime: runtime)
        XCTAssertNotEqual(replacementOwner.processIdentity, owner.processIdentity)
        XCTAssertNotNil(replacementOwner.launchNonce)
        XCTAssertEqual(runtime.inspectProcess(replacementOwner), .gone)
        XCTAssertEqual(try runtime.workersAtExpectedPath().count, 0)
    }

    private func makeLauncher(
        _ runtime: FakeWorkerRuntime,
        attempts: Int = 8
    ) -> HelperLauncher {
        HelperLauncher(runtime: runtime, maximumAttempts: attempts, maximumLaunches: 2)
    }

    private func codesign(
        _ url: URL,
        requirement: String?,
        hardenedRuntime: Bool
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        var arguments = [
            "--force", "--sign", "-",
            "--identifier", TidyTapProduct.helperBundleIdentifier,
            "--timestamp=none"
        ]
        if let requirement {
            arguments += ["--requirements", requirement]
        }
        arguments += (hardenedRuntime ? ["--options", "runtime"] : []) + [url.path]
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HelperLauncherTestError.commandFailed("codesign")
        }
    }

    private func builtHelperURL() -> URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("TidyTap.app")
            .appendingPathComponent(TidyTapProduct.helperExecutablePath)
    }

    private func codeHash(at url: URL) throws -> Data {
        let code = try staticCode(at: url)
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(), &information)
        guard status == errSecSuccess,
              let values = information as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data else {
            throw HelperLauncherTestError.securityStatus(status)
        }
        return hash
    }

    private func designatedRequirement(at url: URL) throws -> String {
        let code = try staticCode(at: url)
        var requirement: SecRequirement?
        let copyStatus = SecCodeCopyDesignatedRequirement(code, SecCSFlags(), &requirement)
        guard copyStatus == errSecSuccess, let requirement else {
            throw HelperLauncherTestError.securityStatus(copyStatus)
        }
        var value: CFString?
        let stringStatus = SecRequirementCopyString(requirement, SecCSFlags(), &value)
        guard stringStatus == errSecSuccess, let value else {
            throw HelperLauncherTestError.securityStatus(stringStatus)
        }
        return value as String
    }

    private func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code)
        guard status == errSecSuccess, let code else {
            throw HelperLauncherTestError.securityStatus(status)
        }
        return code
    }

    private func waitForLockOwner(
        runtime: SystemTidyTapWorkerRuntime,
        process: Process
    ) throws -> TidyTapWorkerLockOwner {
        for _ in 0..<200 {
            if case .held(let owner?) = try runtime.inspectLock(),
               owner.readiness == .acknowledged {
                return owner
            }
            if !process.isRunning {
                throw HelperLauncherTestError.processExited(process.terminationStatus)
            }
            usleep(10_000)
        }
        throw HelperLauncherTestError.workerDidNotStart
    }

    private func waitForFreeAcknowledgement(
        runtime: SystemTidyTapWorkerRuntime
    ) throws -> TidyTapWorkerLockOwner {
        for _ in 0..<200 {
            if case .free(let owner?) = try runtime.inspectLock(),
               owner.readiness == .acknowledged {
                return owner
            }
            usleep(10_000)
        }
        throw HelperLauncherTestError.workerDidNotStart
    }

    private func waitForProcessExit(_ process: Process) throws {
        for _ in 0..<200 {
            if !process.isRunning {
                process.waitUntilExit()
                return
            }
            usleep(10_000)
        }
        throw HelperLauncherTestError.workerDidNotExit
    }

    private func processPath(_ processIdentifier: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * 1_024)
        guard proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

private enum HelperLauncherTestError: Error {
    case commandFailed(String)
    case processExited(Int32)
    case securityStatus(OSStatus)
    case workerDidNotStart
    case workerDidNotExit
}

private final class FakeWorkerRuntime: TidyTapWorkerRuntime {
    private var lockStates: [TidyTapWorkerLockState]
    private var lastLockState: TidyTapWorkerLockState
    private var processStates: [TidyTapWorkerLockOwner: TidyTapWorkerCodeState]
    var pathCandidates: [(TidyTapWorkerLockOwner, TidyTapWorkerCodeState)]
    var clearCandidatesAfterTermination = false
    var acknowledgeAndExitOnLaunch = false
    private var acknowledgedOwner: TidyTapWorkerLockOwner?
    private(set) var launchCount = 0
    private(set) var pauseCount = 0
    private(set) var terminated = [TidyTapWorkerLockOwner]()

    init(
        lockStates: [TidyTapWorkerLockState],
        processStates: [TidyTapWorkerLockOwner: TidyTapWorkerCodeState] = [:],
        pathCandidates: [(TidyTapWorkerLockOwner, TidyTapWorkerCodeState)] = []
    ) {
        self.lockStates = lockStates
        self.lastLockState = lockStates.last ?? .free(lastOwner: nil)
        self.processStates = processStates
        self.pathCandidates = pathCandidates
    }

    func prepare() throws {}

    func inspectLock() throws -> TidyTapWorkerLockState {
        guard !lockStates.isEmpty else {
            if let acknowledgedOwner {
                return .free(lastOwner: acknowledgedOwner)
            }
            return lastLockState
        }
        lastLockState = lockStates.removeFirst()
        return lastLockState
    }

    func inspectProcess(_ owner: TidyTapWorkerLockOwner) -> TidyTapWorkerCodeState {
        processStates[owner] ?? .gone
    }

    func workersAtExpectedPath() throws -> [(TidyTapWorkerLockOwner, TidyTapWorkerCodeState)] {
        pathCandidates
    }

    func launch(nonce: UUID) throws {
        launchCount += 1
        if acknowledgeAndExitOnLaunch {
            acknowledgedOwner = TidyTapWorkerLockOwner(
                processIdentifier: 303,
                startSeconds: 50,
                startMicroseconds: 60,
                readiness: .acknowledged,
                launchNonce: nonce
            )
        }
    }

    func terminate(_ owner: TidyTapWorkerLockOwner) throws {
        terminated.append(owner)
        if clearCandidatesAfterTermination {
            pathCandidates = []
        }
    }

    func pause() {
        pauseCount += 1
    }
}
