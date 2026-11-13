import CloudKit
import CryptoKit
import Foundation
import Security
import TidyTapInputEngine

@MainActor
protocol ClipboardAccountProviding {
    func accountIdentifier() async throws -> String
}

@MainActor
struct CloudKitClipboardAccountProvider: ClipboardAccountProviding {
    let containerIdentifier: String
    func accountIdentifier() async throws -> String {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ProcessInfo.processInfo.environment["TIDYTAP_LAUNCH_SMOKE"] != "1" else { throw ClipboardSyncCoordinator.SyncError.configuration }
        let container = CKContainer(identifier: containerIdentifier)
        guard try await container.accountStatus() == .available else { throw ClipboardSyncCoordinator.SyncError.noAccount }
        let record = try await container.userRecordID()
        return SHA256.hash(data: Data(record.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class ClipboardSyncCoordinator {
    enum State: Equatable { case off, starting, syncing, pausing, waitingAccount, configurationError, failed }
    enum SyncError: Error { case noAccount, configuration }
    private let router: ClipboardLibraryRouter
    private let account: any ClipboardAccountProviding
    private let transport: any ClipboardLibraryMirroring
    private let containerIdentifier: String
    private let preflight: () throws -> Void
    private var generation = 0
    private var transition: Task<Void, Never>?
    private(set) var enabled = false
    private(set) var pauseNeedsRetry = false
    private var ownsMirror = false
    var needsOwnerLifetime: Bool { enabled || ownsMirror || pauseNeedsRetry }
    private(set) var state: State = .off { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    var onAccountWillChange: (() -> Void)?
    var onLibraryChange: (() -> Void)?

    init(router: ClipboardLibraryRouter, account: any ClipboardAccountProviding, transport: any ClipboardLibraryMirroring,
         containerIdentifier: String, preflight: @escaping () throws -> Void) {
        self.router = router; self.account = account; self.transport = transport
        self.containerIdentifier = containerIdentifier; self.preflight = preflight
    }

    func apply(enabled: Bool) {
        self.enabled = enabled; pauseNeedsRetry = false; generation &+= 1
        let request = generation, previous = transition
        state = enabled ? .starting : .pausing
        transition = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == request else { return }
            await self.perform(enabled: enabled, request: request)
        }
    }
    func waitUntilSettled() async { await transition?.value }

    private func perform(enabled: Bool, request: Int) async {
        do { try await transport.stop() }
        catch {
            if generation == request { pauseNeedsRetry = true; state = .pausing }
            return
        }
        ownsMirror = false
        guard generation == request else { return }
        guard enabled else { state = .off; return }
        do {
            try preflight()
            let identifier = try await account.accountIdentifier()
            guard generation == request, self.enabled else { return }
            onAccountWillChange?()
            let route = try router.activateAccount(identifier)
            let directory = try router.withStore(route: route) { store in
                _ = try store.snapshot()
                return store.directory
            }
            ownsMirror = true
            try transport.start(directory: directory, containerIdentifier: containerIdentifier,
                onChange: { [weak self] in
                    guard let self, self.generation == request, self.enabled else { return }
                    self.onLibraryChange?()
                }, onFailure: { [weak self] _ in
                    guard let self, self.generation == request else { return }
                    self.state = .failed
                })
            state = .syncing
        } catch SyncError.noAccount {
            if generation == request { state = .waitingAccount }
        } catch SyncError.configuration {
            if generation == request { state = .configurationError }
        } catch {
            if generation == request { state = .failed }
        }
    }

    static func validateLiveConfiguration(containerIdentifier: String, isTesting: Bool) throws {
        guard !isTesting, !containerIdentifier.isEmpty, !containerIdentifier.contains("$("),
              FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path)
        else { throw SyncError.configuration }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else {
            throw SyncError.configuration
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains(containerIdentifier) == true,
              (entitlements["com.apple.developer.icloud-services"] as? [String])?.contains("CloudKit") == true else {
            throw SyncError.configuration
        }
    }
}
