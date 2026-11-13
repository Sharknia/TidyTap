import AppKit
import CoreData
import Foundation
import TidyTapInputEngine
import XCTest

@MainActor
final class ClipboardSyncCoordinatorTests: XCTestCase {
    private var root: URL!
    private let accountA = String(repeating: "a", count: 64)
    private let accountB = String(repeating: "b", count: 64)
    override func setUp() async throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-sync-\(UUID())") }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }
    private func router() throws -> ClipboardLibraryRouter {
        try ClipboardLibraryRouter(root: root.appendingPathComponent("v2"), legacyDirectory: root.appendingPathComponent("legacy"),
            retention: 600, maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
    }
    private func coordinator(_ router: ClipboardLibraryRouter, _ account: Account, _ mirror: Mirror,
                             preflight: @escaping () throws -> Void = {}) -> ClipboardSyncCoordinator {
        .init(router: router, account: account, transport: mirror, containerIdentifier: "synthetic", preflight: preflight)
    }

    func testConfigurationFailureNeverQueriesAccountOrStartsMirror() async throws {
        let account = Account(accountA), mirror = Mirror()
        let sync = coordinator(try router(), account, mirror, preflight: { throw ClipboardSyncCoordinator.SyncError.configuration })
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .configurationError); XCTAssertTrue(sync.enabled)
        XCTAssertEqual(account.calls, 0); XCTAssertTrue(mirror.directories.isEmpty)
    }

    func testLateOnAccountReplyCannotOverrideOff() async throws {
        let account = Account(accountA); account.hold = true
        let mirror = Mirror(), route = try router()
        let sync = coordinator(route, account, mirror)
        let before = try route.currentRoute()
        sync.apply(enabled: true)
        for _ in 0..<100 where account.continuation == nil { await Task.yield() }
        XCTAssertNotNil(account.continuation)
        sync.apply(enabled: false)
        account.continuation?.resume(returning: accountA); account.continuation = nil
        await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .off); XCTAssertFalse(sync.enabled)
        XCTAssertTrue(mirror.directories.isEmpty); XCTAssertEqual(try route.currentRoute(), before)
    }

    func testPauseResumeUsesSameStoreAndPreservesOfflineCopyAndDelete() async throws {
        let route = try router(), mirror = Mirror(), account = Account(accountA)
        let sync = coordinator(route, account, mirror)
        let h = try route.add(.text(plain: "H", rtf: nil, html: nil))
        sync.apply(enabled: true); await sync.waitUntilSettled()
        sync.apply(enabled: false); await sync.waitUntilSettled()
        _ = try route.add(.text(plain: "X", rtf: nil, html: nil))
        try route.withStore { try $0.delete(h.id) }
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(mirror.directories.count, 2)
        XCTAssertEqual(mirror.directories.first, mirror.directories.last)
        XCTAssertEqual(try route.withStore { try $0.entries().map(\.content) }, [.text(plain: "X", rtf: nil, html: nil)])
        XCTAssertEqual(sync.state, .syncing)
    }

    func testDifferentAccountStartsEmptyAndReturningAccountKeepsItsLibrary() async throws {
        let route = try router(), mirror = Mirror(), account = Account(accountA)
        let sync = coordinator(route, account, mirror)
        _ = try route.add(.text(plain: "A", rtf: nil, html: nil))
        sync.apply(enabled: true); await sync.waitUntilSettled()
        let a = try route.currentRoute()
        account.identifier = accountB
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertTrue(try route.withStore { try $0.entries() }.isEmpty)
        XCTAssertNotEqual(try route.currentRoute(), a)
        account.identifier = accountA
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(try route.currentRoute().folder, a.folder)
        XCTAssertEqual(try route.withStore { try $0.entries().count }, 1)
    }

    func testStopFailureIsNotReportedAsPaused() async throws {
        let mirror = Mirror(), sync = coordinator(try router(), Account(accountA), mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        mirror.stopError = NSError(domain: "synthetic", code: 1)
        sync.apply(enabled: false); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .pausing); XCTAssertFalse(sync.enabled); XCTAssertTrue(sync.pauseNeedsRetry)
        mirror.stopError = nil; sync.apply(enabled: false); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .off); XCTAssertFalse(sync.pauseNeedsRetry)
        XCTAssertEqual(mirror.directories.count, 1)
    }

    func testOldFailureCallbackCannotChangeNewOffState() async throws {
        let mirror = Mirror(), sync = coordinator(try router(), Account(accountA), mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        let old = mirror.failure
        sync.apply(enabled: false); await sync.waitUntilSettled()
        old?(1); XCTAssertEqual(sync.state, .off)
    }

    func testLiveConfigurationIsAlwaysRejectedInTests() {
        XCTAssertThrowsError(try ClipboardSyncCoordinator.validateLiveConfiguration(containerIdentifier: "iCloud.synthetic", isTesting: true))
    }

    func testStaleRouteNeverReachesClipboardWriteClosure() throws {
        let route = try router(), old = try route.currentRoute()
        _ = try route.activateAccount(accountA)
        var writes = 0
        XCTAssertThrowsError(try route.withStore(route: old, requireCurrent: true) { _ in writes += 1 })
        XCTAssertEqual(writes, 0)
    }

    func testPasteIPCParsesRouteAndRejectsMalformedRouting() {
        let generation = UUID()
        var info: [String: Any] = ["sessionID": UUID().uuidString, "entryID": UUID().uuidString,
            "formatted": false, "deadlineContinuousTime": 10.0, "libraryFolder": "local", "libraryGeneration": generation.uuidString]
        let note = { Notification(name: TidyTapIPC.clipboardHistoryPaste, userInfo: info) }
        XCTAssertEqual(TidyTapIPC.clipboardPasteRequest(in: note())?.route?.generation, generation)
        info["libraryFolder"] = "../other"
        XCTAssertNil(TidyTapIPC.clipboardPasteRequest(in: note()))
        info["libraryFolder"] = "local"; info.removeValue(forKey: "libraryGeneration")
        XCTAssertNil(TidyTapIPC.clipboardPasteRequest(in: note()))
    }

    func testSyncPreferenceDoesNotApplyInputOrLaunchHelperAndSurvivesInputFailure() throws {
        let prefs = Preferences(), helper = Helper(), login = Login()
        let coordinator = SettingsCoordinator(preferences: prefs, helperLauncher: helper, loginItemManager: login)
        let request = prefs.request
        try coordinator.saveClipboardICloudSyncEnabled(true)
        XCTAssertTrue(coordinator.readClipboardICloudSyncEnabled())
        XCTAssertEqual(prefs.request.applyRequestID, request.applyRequestID)
        XCTAssertEqual(helper.calls, 0); XCTAssertEqual(login.calls, 0)
        XCTAssertThrowsError(try coordinator.save(.defaults))
        XCTAssertTrue(coordinator.readClipboardICloudSyncEnabled())
        prefs.failSync = true
        XCTAssertThrowsError(try coordinator.saveClipboardICloudSyncEnabled(false))
        XCTAssertTrue(coordinator.readClipboardICloudSyncEnabled())
    }

    func testMissingAccountWaitsAndRetryCanResume() async throws {
        let account = Account(accountA); account.failure = ClipboardSyncCoordinator.SyncError.noAccount
        let mirror = Mirror(), sync = coordinator(try router(), account, mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .waitingAccount); XCTAssertTrue(mirror.directories.isEmpty)
        account.failure = nil; sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .syncing)
    }

    func testProductionProvidersRefuseXCTestBeforeCreatingACloudStore() async throws {
        let mirror = ClipboardLibraryMirror()
        XCTAssertThrowsError(try mirror.start(directory: root.appendingPathComponent("never-created"), containerIdentifier: "iCloud.synthetic",
            onChange: {}, onFailure: { _ in }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("never-created").path))
        do {
            _ = try await CloudKitClipboardAccountProvider(containerIdentifier: "iCloud.synthetic").accountIdentifier()
            XCTFail("live account provider must reject XCTest")
        } catch ClipboardSyncCoordinator.SyncError.configuration { }
    }

    func testStartFailureKeepsLocalLibraryAndShowsApplyError() async throws {
        let route = try router(), mirror = Mirror()
        mirror.startError = NSError(domain: "start", code: 1)
        _ = try route.add(.text(plain: "local", rtf: nil, html: nil))
        let sync = coordinator(route, Account(accountA), mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .failed); XCTAssertTrue(sync.enabled)
        XCTAssertEqual(try route.withStore { try $0.entries().count }, 1)
    }

    func testDelayedStopStaysPausingAndLastOnWins() async throws {
        let mirror = Mirror(), sync = coordinator(try router(), Account(accountA), mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        mirror.holdStop = true; sync.apply(enabled: false)
        for _ in 0..<100 where mirror.stopContinuation == nil { await Task.yield() }
        XCTAssertNotNil(mirror.stopContinuation); XCTAssertEqual(sync.state, .pausing)
        sync.apply(enabled: true)
        mirror.holdStop = false; mirror.stopContinuation?.resume(); mirror.stopContinuation = nil
        await sync.waitUntilSettled()
        XCTAssertEqual(sync.state, .syncing); XCTAssertTrue(sync.enabled)
        XCTAssertEqual(mirror.directories.count, 2)
    }

    func testLateLibraryChangeAfterOffIsIgnored() async throws {
        let mirror = Mirror(), sync = coordinator(try router(), Account(accountA), mirror)
        var changes = 0; sync.onLibraryChange = { changes += 1 }
        sync.apply(enabled: true); await sync.waitUntilSettled()
        let old = mirror.change
        sync.apply(enabled: false); await sync.waitUntilSettled()
        old?(); XCTAssertEqual(changes, 0)
    }

    func testTemporaryHostLifetimeIsPreservedOnlyWhenSyncNeedsIt() async throws {
        let mirror = Mirror(), sync = coordinator(try router(), Account(accountA), mirror)
        XCTAssertFalse(sync.needsOwnerLifetime)
        sync.apply(enabled: false); XCTAssertFalse(sync.needsOwnerLifetime)
        await sync.waitUntilSettled()
        sync.apply(enabled: true); XCTAssertTrue(sync.needsOwnerLifetime)
        await sync.waitUntilSettled()
        mirror.holdStop = true; sync.apply(enabled: false)
        for _ in 0..<100 where mirror.stopContinuation == nil { await Task.yield() }
        XCTAssertTrue(sync.needsOwnerLifetime)
        mirror.holdStop = false; mirror.stopContinuation?.resume(); mirror.stopContinuation = nil
        await sync.waitUntilSettled(); XCTAssertFalse(sync.needsOwnerLifetime)
    }

    func testTestProcessCannotOpenProductionLibraryByMissingSuite() {
        XCTAssertThrowsError(try TidyTapProduct.clipboardRouter(directory: TidyTapProduct.clipboardHistoryDirectory()))
    }

    func testResumeDeletesExpiredOfflineHistoryBeforeTransportStarts() async throws {
        let route = try router(), mirror = Mirror()
        _ = try route.add(.text(plain: "expired", rtf: nil, html: nil), copiedAt: Date().addingTimeInterval(-601))
        var inspected = false
        mirror.inspectStart = { directory in
            let raw = NSPersistentContainer(name: "expiry-check", managedObjectModel: ClipboardLibraryStore.managedObjectModel())
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent(ClipboardLibraryStore.fileName))
            description.shouldAddStoreAsynchronously = false
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            raw.persistentStoreDescriptions = [description]
            var failure: Error?; raw.loadPersistentStores { _, error in failure = error }
            if let failure { throw failure }
            XCTAssertEqual(try raw.viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "LibraryHistory")), 0)
            inspected = true
        }
        let sync = coordinator(route, Account(accountA), mirror)
        sync.apply(enabled: true); await sync.waitUntilSettled()
        XCTAssertTrue(inspected); XCTAssertEqual(sync.state, .syncing)
    }

    func testLegacyMigrationRequiresCurrentWriterBeforeOpeningOldFiles() throws {
        let directory = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("one.clip"); try Data("original".utf8).write(to: old)
        var called = 0
        XCTAssertThrowsError(try TidyTapProduct.prepareClipboardLegacyMigration(directory: directory) {
            called += 1; throw TidyTapPreferencesError.persistenceFailed
        })
        XCTAssertEqual(called, 1); XCTAssertEqual(try Data(contentsOf: old), Data("original".utf8))
        let marker = directory.appendingPathComponent("clipboard-library-v2/legacy-imported")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: marker)
        XCTAssertNoThrow(try TidyTapProduct.prepareClipboardLegacyMigration(directory: directory) { XCTFail("no reimport after completed migration") })
    }

    @MainActor private final class Account: ClipboardAccountProviding {
        var identifier: String; var calls = 0; var hold = false; var failure: Error?
        var continuation: CheckedContinuation<String, Error>?
        init(_ value: String) { identifier = value }
        func accountIdentifier() async throws -> String {
            calls += 1
            if let failure { throw failure }
            if hold { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return identifier
        }
    }
    @MainActor private final class Mirror: ClipboardLibraryMirroring {
        var directories = [URL](); var stopError: Error?; var startError: Error?
        var inspectStart: ((URL) throws -> Void)?
        var holdStop = false; var stopContinuation: CheckedContinuation<Void, Never>?
        var change: (@MainActor () -> Void)?
        var failure: (@MainActor (Int) -> Void)?
        func start(directory: URL, containerIdentifier: String, onChange: @escaping @MainActor () -> Void,
                   onFailure: @escaping @MainActor (Int) -> Void) throws {
            if let startError { throw startError }
            try inspectStart?(directory)
            directories.append(directory); failure = onFailure; change = onChange
        }
        func stop() async throws {
            if let stopError { throw stopError }
            if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
        }
    }
    private final class Preferences: TidyTapPreferencesStoring {
        var request = TidyTapSettingsRequest(settings: .defaults, applyRequestID: UUID())
        var enabled = false; var failSync = false
        func readClipboardICloudSyncEnabled() -> Bool { enabled }
        func writeClipboardICloudSyncEnabled(_ value: Bool) throws {
            if failSync { throw TidyTapPreferencesError.persistenceFailed }; enabled = value
        }
        func readRequest() -> TidyTapSettingsRequest { request }
        func write(settings: TidyTapSettings, applyRequestID: UUID) throws { request = .init(settings: settings, applyRequestID: applyRequestID) }
        func readApplyStatus() -> TidyTapApplyStatus? { nil }
        func writeApplyStatus(_ status: TidyTapApplyStatus) throws { }
        func readPermissionRequest() -> TidyTapPermissionRequest? { nil }
        func writePermissionRequest(_ request: TidyTapPermissionRequest) throws { }
        func readPermissionResult() -> TidyTapPermissionResult? { nil }
        func writePermissionResult(_ result: TidyTapPermissionResult) throws { }
    }
    private final class Helper: TidyTapHelperLaunching {
        var calls = 0
        func ensureHelperRunning() throws { calls += 1; throw TidyTapPreferencesError.persistenceFailed }
    }
    private final class Login: TidyTapLoginItemManaging {
        var calls = 0
        func setEnabled(_ enabled: Bool) throws { calls += 1 }
        func status() -> TidyTapLoginItemStatus { .disabled }
    }
}
