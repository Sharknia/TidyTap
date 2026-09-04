import XCTest
@testable import TidyTapInputEngine

final class FakeSystemApplyAdapter: HIDMappingApplying, SymbolicHotkeyApplying, InputSourceCounting, @unchecked Sendable {
    var hidMappings: [HIDMapping]
    var hotkeyDomain: PropertyListDictionary
    var hidApplyCount = 0
    var hotkeyApplyCount = 0
    var activationCount = 0
    var failHIDApplyNumbers: Set<Int> = []
    var failHotkeyApplyNumbers: Set<Int> = []
    var failActivationNumbers: Set<Int> = []
    var inputSourceCount = 2
    var hidReadCount = 0
    var hotkeyReadCount = 0
    var onHIDRead: ((Int) -> Void)?
    var onHotkeyRead: ((Int) -> Void)?

    init(
        hidMappings: [HIDMapping] = [],
        hotkeyDomain: PropertyListDictionary = [:]
    ) {
        self.hidMappings = hidMappings
        self.hotkeyDomain = hotkeyDomain
    }

    func readHIDMappings() throws -> [HIDMapping] {
        hidReadCount += 1
        onHIDRead?(hidReadCount)
        return hidMappings
    }

    func applyHIDMappings(_ mappings: [HIDMapping]) throws {
        hidApplyCount += 1
        if failHIDApplyNumbers.contains(hidApplyCount) { throw TestFailure.requested }
        hidMappings = mappings
    }

    func readSymbolicHotkeyDomain() throws -> PropertyListDictionary {
        hotkeyReadCount += 1
        onHotkeyRead?(hotkeyReadCount)
        return hotkeyDomain
    }

    func applySymbolicHotkeyDomain(_ domain: PropertyListDictionary) throws {
        hotkeyApplyCount += 1
        if failHotkeyApplyNumbers.contains(hotkeyApplyCount) { throw TestFailure.requested }
        hotkeyDomain = domain
    }

    func activateSymbolicHotkeySettings() throws {
        activationCount += 1
        if failActivationNumbers.contains(activationCount) { throw TestFailure.requested }
    }

    func enabledSelectableInputSourceCount() throws -> Int { inputSourceCount }
}

private enum TestFailure: Error {
    case requested
}

final class CapsLockControllerTests: XCTestCase {
    func testEnableAppendsOnlyOwnedMappingAndReturnsOwnership() throws {
        let unrelated = HIDMapping(source: 1, destination: 2)
        let system = FakeSystemApplyAdapter(hidMappings: [unrelated])
        let controller = CapsLockController(system: system)

        let change = try controller.prepareEnable()
        try controller.commit(change)

        XCTAssertEqual(system.hidMappings, [unrelated, .tidyTapCapsLock])
        XCTAssertEqual(change.ownershipAfterCommit, .current)
    }

    func testEnableRefusesOtherCapsMapping() {
        let system = FakeSystemApplyAdapter(hidMappings: [
            HIDMapping(source: HIDMapping.capsLockSource, destination: 99)
        ])
        let controller = CapsLockController(system: system)

        XCTAssertThrowsError(try controller.prepareEnable()) {
            XCTAssertEqual($0 as? InputEngineError, .capsLockAlreadyMapped)
        }
    }

    func testEnableDoesNotClaimIdenticalMappingWithoutOwnershipRecord() {
        let controller = CapsLockController(
            system: FakeSystemApplyAdapter(hidMappings: [.tidyTapCapsLock])
        )

        XCTAssertThrowsError(try controller.prepareEnable()) {
            XCTAssertEqual($0 as? InputEngineError, .capsLockAlreadyMapped)
        }
    }

    func testExistingOwnershipMakesRestartIdempotent() throws {
        let system = FakeSystemApplyAdapter(hidMappings: [.tidyTapCapsLock])
        let controller = CapsLockController(system: system)

        let change = try controller.prepareEnable(existingOwnership: .current)
        try controller.commit(change)

        XCTAssertEqual(system.hidApplyCount, 0)
        XCTAssertEqual(system.hidMappings, [.tidyTapCapsLock])
    }

    func testExistingOwnershipRejectsLostMapping() {
        let controller = CapsLockController(system: FakeSystemApplyAdapter())

        XCTAssertThrowsError(try controller.prepareEnable(existingOwnership: .current)) {
            XCTAssertEqual($0 as? InputEngineError, .capsLockOwnershipConflict)
        }
    }

    func testExistingOwnershipRejectsUnknownOwnershipVersion() {
        let controller = CapsLockController(
            system: FakeSystemApplyAdapter(hidMappings: [.tidyTapCapsLock])
        )

        XCTAssertThrowsError(
            try controller.prepareEnable(existingOwnership: CapsHIDOwnership(version: 99))
        ) {
            XCTAssertEqual($0 as? InputEngineError, .capsLockOwnershipConflict)
        }
    }

    func testCommitRejectsStateChangedAfterPreparation() throws {
        let system = FakeSystemApplyAdapter()
        let controller = CapsLockController(system: system)
        let change = try controller.prepareEnable()
        system.hidMappings.append(HIDMapping(source: 7, destination: 8))

        XCTAssertThrowsError(try controller.commit(change)) {
            XCTAssertEqual($0 as? InputEngineError, .preWriteStateChanged(.hidMappings))
        }
        XCTAssertEqual(system.hidApplyCount, 0)
    }

    func testDisableRemovesOneOwnedPairAndPreservesLiveUnrelatedMappings() throws {
        let unrelated = HIDMapping(source: 7, destination: 8)
        let thirdPartyCaps = HIDMapping(source: HIDMapping.capsLockSource, destination: 9)
        let system = FakeSystemApplyAdapter(
            hidMappings: [.tidyTapCapsLock, unrelated, thirdPartyCaps]
        )
        let controller = CapsLockController(system: system)

        let change = try controller.prepareDisable(ownership: .current)
        try controller.commit(change)

        XCTAssertEqual(system.hidMappings, [unrelated, thirdPartyCaps])
    }

    func testDisableRejectsMissingOrDuplicateOwnedPair() {
        let cases: [[HIDMapping]] = [[], [.tidyTapCapsLock, .tidyTapCapsLock]]
        for mappings in cases {
            let controller = CapsLockController(
                system: FakeSystemApplyAdapter(hidMappings: mappings)
            )
            XCTAssertThrowsError(try controller.prepareDisable(ownership: .current)) {
                XCTAssertEqual($0 as? InputEngineError, .capsLockOwnershipConflict)
            }
        }
    }

    func testRollbackRefusesToOverwriteExternalChange() throws {
        let system = FakeSystemApplyAdapter()
        let controller = CapsLockController(system: system)
        let change = try controller.prepareEnable()
        try controller.commit(change)
        system.hidMappings.append(HIDMapping(source: 4, destination: 5))

        XCTAssertThrowsError(try controller.rollbackIfApplied(change)) {
            XCTAssertEqual($0 as? InputEngineError, .staleSystemState(.hidMappings))
        }
        XCTAssertEqual(system.hidApplyCount, 1)
    }
}

final class InputSourceShortcutControllerTests: XCTestCase {
    private let backup: PropertyListValue = .dictionary(["enabled": .bool(false)])

    func testEnableBacksUp60AndPreservesWholeDomain() throws {
        let original: PropertyListDictionary = [
            "AppleSymbolicHotKeys": .dictionary([
                "60": backup,
                "61": .dictionary(["enabled": .bool(true)])
            ]),
            "UnrelatedDomainKey": .string("keep")
        ]
        let system = FakeSystemApplyAdapter(hotkeyDomain: original)
        let controller = InputSourceShortcutController(system: system)

        let change = try controller.prepareEnable()
        try controller.commit(change)

        XCTAssertEqual(change.ownershipAfterCommit?.backup, backup)
        XCTAssertEqual(
            InputSourceShortcutController.hotkey60(in: system.hotkeyDomain),
            .tidyTapHotkey60
        )
        XCTAssertEqual(system.hotkeyDomain["UnrelatedDomainKey"], .string("keep"))
        guard case .dictionary(let hotkeys)? = system.hotkeyDomain["AppleSymbolicHotKeys"] else {
            return XCTFail("missing hotkeys dictionary")
        }
        XCTAssertNotNil(hotkeys["61"])
        XCTAssertEqual(system.activationCount, 1)
    }

    func testEnableRefusesIdenticalValueWithoutOwnership() {
        let domain = InputSourceShortcutController.replacingHotkey60(
            in: [:],
            with: .tidyTapHotkey60
        )
        let controller = InputSourceShortcutController(
            system: FakeSystemApplyAdapter(hotkeyDomain: domain)
        )

        XCTAssertThrowsError(try controller.prepareEnable()) {
            XCTAssertEqual($0 as? InputEngineError, .symbolicHotkeyOwnershipConflict)
        }
    }

    func testDisableRestoresBackupOnlyWhileTidyTapStillOwns60() throws {
        let owned = InputSourceShortcutController.replacingHotkey60(
            in: ["Other": .integer(2)],
            with: .tidyTapHotkey60
        )
        let system = FakeSystemApplyAdapter(hotkeyDomain: owned)
        let controller = InputSourceShortcutController(system: system)

        let change = try controller.prepareDisable(ownership: Hotkey60Ownership(backup: backup))
        try controller.commit(change)

        XCTAssertEqual(InputSourceShortcutController.hotkey60(in: system.hotkeyDomain), backup)
        XCTAssertEqual(system.hotkeyDomain["Other"], .integer(2))
    }

    func testDisableLeavesUserChanged60Untouched() {
        let changed = InputSourceShortcutController.replacingHotkey60(
            in: [:],
            with: .dictionary(["enabled": .bool(false)])
        )
        let system = FakeSystemApplyAdapter(hotkeyDomain: changed)
        let controller = InputSourceShortcutController(system: system)

        XCTAssertThrowsError(
            try controller.prepareDisable(ownership: Hotkey60Ownership(backup: backup))
        ) {
            XCTAssertEqual($0 as? InputEngineError, .symbolicHotkeyOwnershipConflict)
        }
        XCTAssertEqual(system.hotkeyApplyCount, 0)
    }

    func testCommitAndRollbackBothUseFreshWholeDomainChecks() throws {
        let system = FakeSystemApplyAdapter(hotkeyDomain: ["A": .integer(1)])
        let controller = InputSourceShortcutController(system: system)
        let change = try controller.prepareEnable()
        system.hotkeyDomain["B"] = .integer(2)

        XCTAssertThrowsError(try controller.commit(change)) {
            XCTAssertEqual($0 as? InputEngineError, .preWriteStateChanged(.symbolicHotkey60))
        }

        system.hotkeyDomain = change.before
        try controller.commit(change)
        system.hotkeyDomain["B"] = .integer(2)
        XCTAssertThrowsError(try controller.rollbackIfApplied(change)) {
            XCTAssertEqual($0 as? InputEngineError, .staleSystemState(.symbolicHotkey60))
        }
    }

    func testAbsentHotkeysContainerIsRemovedAgainOnRestore() throws {
        let original: PropertyListDictionary = ["Other": .string("keep")]
        let system = FakeSystemApplyAdapter(hotkeyDomain: original)
        let controller = InputSourceShortcutController(system: system)

        let enable = try controller.prepareEnable()
        let ownership = try XCTUnwrap(enable.ownershipAfterCommit)
        try controller.commit(enable)
        let disable = try controller.prepareDisable(ownership: ownership)
        try controller.commit(disable)

        XCTAssertEqual(system.hotkeyDomain, original)
    }

    func testMalformedHotkeysContainerIsNeverOverwritten() {
        let original: PropertyListDictionary = ["AppleSymbolicHotKeys": .string("invalid")]
        let system = FakeSystemApplyAdapter(hotkeyDomain: original)
        let controller = InputSourceShortcutController(system: system)

        XCTAssertThrowsError(try controller.prepareEnable()) {
            XCTAssertEqual($0 as? InputEngineError, .invalidSystemData(.symbolicHotkey60))
        }
        XCTAssertEqual(system.hotkeyDomain, original)
        XCTAssertEqual(system.hotkeyApplyCount, 0)
    }
}

final class CapsLockFeatureControllerTests: XCTestCase {
    private var originalDomain: PropertyListDictionary {
        InputSourceShortcutController.replacingHotkey60(
            in: ["Other": .string("keep")],
            with: .dictionary(["enabled": .bool(false)])
        )
    }

    func testEnableAndDisableRoundTrip() throws {
        let unrelated = HIDMapping(source: 1, destination: 2)
        let system = FakeSystemApplyAdapter(
            hidMappings: [unrelated],
            hotkeyDomain: originalDomain
        )
        let feature = makeFeature(system)

        let ownership = try feature.enable()
        XCTAssertEqual(system.hidMappings, [unrelated, .tidyTapCapsLock])
        XCTAssertEqual(
            InputSourceShortcutController.hotkey60(in: system.hotkeyDomain),
            .tidyTapHotkey60
        )

        try feature.disable(ownership: ownership)
        XCTAssertEqual(system.hidMappings, [unrelated])
        XCTAssertEqual(system.hotkeyDomain, originalDomain)
    }

    func testEnableRequiresExactlyTwoInputSourcesBeforeMutation() throws {
        for count in [1, 3] {
            let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
            system.inputSourceCount = count
            let feature = makeFeature(system)

            XCTAssertThrowsError(try feature.enable()) {
                XCTAssertEqual($0 as? InputEngineError, .invalidInputSourceCount(count))
            }
            XCTAssertEqual(system.hidApplyCount, 0)
            XCTAssertEqual(system.hotkeyApplyCount, 0)
            XCTAssertEqual(system.activationCount, 0)
        }

        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.inputSourceCount = 2
        _ = try makeFeature(system).enable()
        XCTAssertEqual(system.hidApplyCount, 1)
        XCTAssertEqual(system.hotkeyApplyCount, 1)
    }

    func testHIDPreWriteStateChangeDoesNotReportFalseRecoveryRequirement() {
        let external = HIDMapping(source: 8, destination: 9)
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.onHIDRead = { read in
            if read == 2 { system.hidMappings = [external] }
        }

        XCTAssertThrowsError(try makeFeature(system).enable()) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.recoveryRequired, false)
            XCTAssertEqual(failure?.rollbackIssues, [])
        }
        XCTAssertEqual(system.hidApplyCount, 0)
        XCTAssertEqual(system.hotkeyApplyCount, 0)
        XCTAssertEqual(system.hidMappings, [external])
    }

    func testHotkeyPreWriteStateChangeRollsBackOnlyPriorHIDChange() {
        let externalDomain: PropertyListDictionary = ["External": .integer(1)]
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.onHotkeyRead = { read in
            if read == 2 { system.hotkeyDomain = externalDomain }
        }

        XCTAssertThrowsError(try makeFeature(system).enable()) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.recoveryRequired, false)
            XCTAssertEqual(failure?.rollbackIssues, [])
        }
        XCTAssertEqual(system.hidApplyCount, 2, "the earlier HID commit is rolled back")
        XCTAssertEqual(system.hotkeyApplyCount, 0, "the rejected hotkey write needs no rollback")
        XCTAssertEqual(system.hidMappings, [])
        XCTAssertEqual(system.hotkeyDomain, externalDomain)
    }

    func testHotkeyApplyFailureRollsBackHID() {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.failHotkeyApplyNumbers = [1]
        let feature = makeFeature(system)

        XCTAssertThrowsError(try feature.enable()) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.rollbackIssues, [])
        }
        XCTAssertEqual(system.hidMappings, [])
        XCTAssertEqual(system.hidApplyCount, 2)
        XCTAssertEqual(system.hotkeyDomain, originalDomain)
    }

    func testActivationFailureRollsBackBothAppliedChanges() {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.failActivationNumbers = [1]
        let feature = makeFeature(system)

        XCTAssertThrowsError(try feature.enable()) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.rollbackIssues, [])
        }
        XCTAssertEqual(system.hidMappings, [])
        XCTAssertEqual(system.hotkeyDomain, originalDomain)
        XCTAssertEqual(system.activationCount, 2)
    }

    func testRollbackFailureIsReported() {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        system.failHotkeyApplyNumbers = [1]
        system.failHIDApplyNumbers = [2]
        let feature = makeFeature(system)

        XCTAssertThrowsError(try feature.enable()) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.rollbackIssues.map(\.component), [.hidMappings])
        }
        XCTAssertEqual(system.hidMappings, [.tidyTapCapsLock])
    }

    func testDisableHIDFailureRestoresHotkeyOwnership() throws {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        let feature = makeFeature(system)
        let ownership = try feature.enable()
        system.failHIDApplyNumbers = [2]

        XCTAssertThrowsError(try feature.disable(ownership: ownership)) {
            let failure = $0 as? TransactionFailure
            XCTAssertEqual(failure?.rollbackIssues, [])
        }
        XCTAssertEqual(system.hidMappings, [.tidyTapCapsLock])
        XCTAssertEqual(
            InputSourceShortcutController.hotkey60(in: system.hotkeyDomain),
            .tidyTapHotkey60
        )
    }

    func testPreparedEnableCompletesAfterHIDOnlyCrash() throws {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        let feature = makeFeature(system)
        let plan = try feature.prepareEnablePlan()
        system.hidMappings = plan.hid.after

        let ownership = try feature.completePreparedEnable(plan)

        XCTAssertEqual(ownership, plan.ownership)
        XCTAssertEqual(system.hidMappings, [.tidyTapCapsLock])
        XCTAssertEqual(
            InputSourceShortcutController.hotkey60(in: system.hotkeyDomain),
            .tidyTapHotkey60
        )
        XCTAssertEqual(system.hotkeyApplyCount, 1)
        XCTAssertEqual(system.activationCount, 1)
    }

    func testPreparedEnableReactivatesAfterHotkeyWriteBeforeActivateCrash() throws {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        let feature = makeFeature(system)
        let plan = try feature.prepareEnablePlan()
        system.hidMappings = plan.hid.after
        system.hotkeyDomain = plan.hotkey60.after

        _ = try feature.completePreparedEnable(plan)

        XCTAssertEqual(system.hidApplyCount, 0)
        XCTAssertEqual(system.hotkeyApplyCount, 0)
        XCTAssertEqual(system.activationCount, 1)
    }

    func testRebootRecoveryReappliesOnlyMissingHIDWhenHotkeySurvives() throws {
        let system = FakeSystemApplyAdapter(hotkeyDomain: originalDomain)
        let feature = makeFeature(system)
        let ownership = try feature.enable()
        system.hidMappings = []
        let hotkeyWritesBeforeRecovery = system.hotkeyApplyCount

        try feature.recoverHIDAfterReset(ownership: ownership)

        XCTAssertEqual(system.hidMappings, [.tidyTapCapsLock])
        XCTAssertEqual(system.hotkeyApplyCount, hotkeyWritesBeforeRecovery)
        XCTAssertEqual(
            InputSourceShortcutController.hotkey60(in: system.hotkeyDomain),
            .tidyTapHotkey60
        )
    }

    private func makeFeature(_ system: FakeSystemApplyAdapter) -> CapsLockFeatureController {
        CapsLockFeatureController(
            hid: CapsLockController(system: system),
            hotkey: InputSourceShortcutController(system: system),
            inputSources: system
        )
    }
}
