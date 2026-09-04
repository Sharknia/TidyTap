import XCTest
@testable import CapsLockProbeCore

final class CapsLockProbeCoreTests: XCTestCase {
    func testApplyPreservesUnrelatedMappings() throws {
        let unrelated = HIDMapping(source: 0x7000000E0, destination: 0x7000000E1)
        XCTAssertEqual(try HIDMappingMerger.apply(to: [unrelated]), [unrelated, .tidyTapCapsLock])
    }

    func testApplyRejectsOtherCapsLockOwnership() {
        XCTAssertThrowsError(try HIDMappingMerger.apply(to: [HIDMapping(source: HIDMapping.capsLockSource, destination: 0x700000029)])) {
            XCTAssertEqual($0 as? ProbeError, .capsLockOwnedByAnotherMapping)
        }
    }

    func testApplyRejectsMixedTidyTapAndConflictingCapsOwnership() {
        let conflict = HIDMapping(source: HIDMapping.capsLockSource, destination: 0x700000029)
        XCTAssertThrowsError(try HIDMappingMerger.apply(to: [.tidyTapCapsLock, conflict]))
    }

    func testDecodesOpenStepHIDUtilArray() throws {
        let sample = "( { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; } )".data(using: .utf8)!
        XCTAssertEqual(try SystemProbe.decodeHIDMappings(sample), [.tidyTapCapsLock])
    }

    func testRemoveDeletesOnlyTidyTapPair() {
        let otherCaps = HIDMapping(source: HIDMapping.capsLockSource, destination: 0x700000029)
        let unrelated = HIDMapping(source: 9, destination: 10)
        XCTAssertEqual(HIDMappingMerger.removeTidyTap(from: [otherCaps, .tidyTapCapsLock, unrelated]), [otherCaps, unrelated])
    }

    func testRestorePreservesChangedHotkeyAsConflict() {
        let changed: [String: Any] = ["60": ["enabled": false]]
        XCTAssertThrowsError(try SymbolicHotkey60.restore(current: changed, backup: ["enabled": true])) {
            XCTAssertEqual($0 as? ProbeError, .symbolicHotkeyChanged)
        }
    }

    func testRestoreUsesBackupOnlyWhenOwned() throws {
        let backup: [String: Any] = ["enabled": false]
        let restored = try SymbolicHotkey60.restore(current: ["60": SymbolicHotkey60.tidyTapValue(), "61": ["enabled": true]], backup: backup)
        XCTAssertTrue(SymbolicHotkey60.plistEqual(restored["60"], backup))
        XCTAssertNotNil(restored["61"])
    }
}
