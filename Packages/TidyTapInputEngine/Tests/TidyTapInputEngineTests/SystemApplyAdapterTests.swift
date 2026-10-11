import XCTest
@testable import TidyTapInputEngine

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation {
        let executable: String
        let arguments: [String]
        let input: Data?
    }

    var outputs: [Data]
    var invocations: [Invocation] = []
    var failingInvocation: Int?

    init(outputs: [Data] = []) {
        self.outputs = outputs
    }

    func run(executable: String, arguments: [String], input: Data?) throws -> Data {
        invocations.append(.init(executable: executable, arguments: arguments, input: input))
        if invocations.count == failingInvocation {
            throw InputEngineError.commandFailed(executable: executable, status: 1, detail: "fixture failure")
        }
        return outputs.isEmpty ? Data() : outputs.removeFirst()
    }
}

final class SystemApplyAdapterTests: XCTestCase {
    private let keyboardScope = ["--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"]

    private func table(_ values: [String]) -> Data {
        Data(("RegistryID  Key                   Value\n" + values.enumerated().map {
            "\(String(0x100000001 + $0.offset, radix: 16))   UserKeyMapping   \($0.element)"
        }.joined(separator: "\n")).utf8)
    }

    private let capsArray = """
    (
      {
        HIDKeyboardModifierMappingDst = 30064771181;
        HIDKeyboardModifierMappingSrc = 30064771129;
      }
    )
    """

    func testDecodesIdenticalMultilineArraysAndCRLF() throws {
        let payload = table([capsArray, capsArray])
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(payload), [.tidyTapCapsLock])
        let crlf = String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(Data(crlf.utf8)), [.tidyTapCapsLock])
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(table(["(null)", "()"])), [])
    }

    func testTablePreservesUnrelatedMappings() throws {
        let array = "( { HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; }, { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; } )"
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(table([array, array])), [
            HIDMapping(source: 1, destination: 2), .tidyTapCapsLock
        ])
    }

    func testRejectsDivergentAndMalformedTables() {
        let malformed = [
            table(["(null)", capsArray]),
            table([capsArray, "({ HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; })"]),
            table([capsArray, "({ HIDKeyboardModifierMappingSrc = 1; })"]),
            table(["(null) trailing"]),
            table([capsArray + " trailing"]),
            table([capsArray + " ()"]),
            table([String(capsArray.dropLast())]),
            table(["[]"]),
            Data("RegistryID Key Value\n".utf8),
            Data("RegistryID Key Value\n100000001 UserKeyMapping (null)\n100000001 UserKeyMapping (null)".utf8),
            Data("RegistryID Key Value\n100000001 WrongKey (null)".utf8),
            Data("RegistryID Key Value\nNOT_HEX UserKeyMapping (null)".utf8),
            Data("RegistryID Key Value\n100000001 UserKeyMapping (null)\n100000002 UserKeyMapping".utf8),
            Data("RegistryID Key Value\ngarbage\n100000001 UserKeyMapping (null)".utf8)
        ]
        for payload in malformed {
            XCTAssertThrowsError(try MacOSSystemApplyAdapter.decodeHIDMappings(payload)) {
                XCTAssertEqual($0 as? InputEngineError, .invalidSystemData(.hidMappings))
            }
        }
    }

    func testXMLLegacyReadKeepsUnscopedCommands() throws {
        let mappings: [[String: UInt64]] = [["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2]]
        let xml = try PropertyListSerialization.data(fromPropertyList: mappings, format: .xml, options: 0)
        let runner = FakeProcessRunner(outputs: [xml, xml])
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        XCTAssertEqual(try adapter.readHIDMappings(), [HIDMapping(source: 1, destination: 2)])
        XCTAssertEqual(try adapter.readHIDMappings(), [HIDMapping(source: 1, destination: 2)])
        try adapter.applyHIDMappings([])
        XCTAssertEqual(runner.invocations[0].arguments, ["property", "--get", "UserKeyMapping"])
        XCTAssertEqual(runner.invocations[1].arguments, ["property", "--get", "UserKeyMapping"])
        XCTAssertEqual(runner.invocations[2].arguments.prefix(2), ["property", "--set"])
    }

    func testTableScopeStaysFixedForReadsWritesAndRollback() throws {
        let empty = table(["(null)", "(null)"])
        let mapped = table([capsArray, capsArray])
        let runner = FakeProcessRunner(outputs: [empty, empty, Data(), mapped, Data(), empty])
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        XCTAssertEqual(try adapter.readHIDMappings(), [])
        try adapter.applyHIDMappings([.tidyTapCapsLock])
        XCTAssertEqual(try adapter.readHIDMappings(), [.tidyTapCapsLock])
        try adapter.applyHIDMappings([])
        XCTAssertEqual(try adapter.readHIDMappings(), [])
        XCTAssertEqual(runner.invocations.first?.arguments, ["property", "--get", "UserKeyMapping"])
        for call in runner.invocations.dropFirst() {
            XCTAssertEqual(Array(call.arguments.prefix(3)), ["property"] + keyboardScope)
        }
    }

    func testDirectWriteDiscoversScopeAndRefusesMalformedInitialState() throws {
        let empty = table(["(null)"])
        let runner = FakeProcessRunner(outputs: [empty, empty])
        try MacOSSystemApplyAdapter(runner: runner).applyHIDMappings([.tidyTapCapsLock])
        XCTAssertEqual(runner.invocations.count, 3)
        XCTAssertEqual(Array(runner.invocations.last!.arguments.prefix(4)), ["property"] + keyboardScope + ["--set"])

        for outputs in [[Data()], [empty, table(["(null)", capsArray])]] {
            let rejected = FakeProcessRunner(outputs: outputs)
            XCTAssertThrowsError(try MacOSSystemApplyAdapter(runner: rejected).applyHIDMappings([]))
            XCTAssertFalse(rejected.invocations.contains { $0.arguments.contains("--set") })
        }
    }

    func testMatchedFailureNeverFallsBackToUnscoped() throws {
        let empty = table(["(null)"])
        let runner = FakeProcessRunner(outputs: [empty, empty])
        runner.failingInvocation = 2
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        XCTAssertThrowsError(try adapter.readHIDMappings())
        runner.failingInvocation = nil
        XCTAssertEqual(try adapter.readHIDMappings(), [])
        try adapter.applyHIDMappings([])
        for call in runner.invocations.dropFirst() {
            XCTAssertEqual(Array(call.arguments.prefix(3)), ["property"] + keyboardScope)
        }
    }

    func testScopeDoesNotChangeWhenRepresentationChanges() throws {
        let empty = table(["(null)"])
        for outputs in [[Data("(null)".utf8), empty], [empty, empty, Data("(null)".utf8)]] {
            let runner = FakeProcessRunner(outputs: outputs)
            let adapter = MacOSSystemApplyAdapter(runner: runner)
            _ = try adapter.readHIDMappings()
            XCTAssertThrowsError(try adapter.readHIDMappings())
            XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("--set") })
        }
    }

    func testFailedMatchedReadCannotAuthorizeDirectWrite() throws {
        let empty = table(["(null)"])
        let mixed = table(["(null)", capsArray])
        let runner = FakeProcessRunner(outputs: [empty, mixed, mixed])
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        XCTAssertThrowsError(try adapter.readHIDMappings())
        XCTAssertThrowsError(try adapter.applyHIDMappings([]))
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("--set") })
    }

    func testDifferentOrderOfDeviceMappingsIsNotMerged() {
        let first = "({ HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; }, { HIDKeyboardModifierMappingSrc = 3; HIDKeyboardModifierMappingDst = 4; })"
        let reversed = "({ HIDKeyboardModifierMappingSrc = 3; HIDKeyboardModifierMappingDst = 4; }, { HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; })"
        XCTAssertThrowsError(try MacOSSystemApplyAdapter.decodeHIDMappings(table([first, reversed])))
    }

    func testControllerRejectsHotplugBeforeWrite() throws {
        let empty = table(["(null)", "(null)"])
        let runner = FakeProcessRunner(outputs: [empty, empty, table(["(null)", capsArray])])
        let controller = CapsLockController(system: MacOSSystemApplyAdapter(runner: runner))
        let change = try controller.prepareEnable()
        XCTAssertThrowsError(try controller.commit(change))
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("--set") })
    }

    func testControllerRejectsPartialWriteAndDoesNotOverwriteDuringRollback() throws {
        let empty = table(["(null)", "(null)"])
        let mixed = table([capsArray, "(null)"])
        let runner = FakeProcessRunner(outputs: [empty, empty, empty, Data(), mixed, mixed])
        let controller = CapsLockController(system: MacOSSystemApplyAdapter(runner: runner))
        let change = try controller.prepareEnable()
        XCTAssertThrowsError(try controller.commit(change))
        XCTAssertThrowsError(try controller.rollbackIfApplied(change))
        XCTAssertEqual(runner.invocations.filter { $0.arguments.contains("--set") }.count, 1)
    }

    func testLiveHIDReadOnlyWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["TIDYTAP_VERIFY_LIVE_HID_READ"] == "1" else {
            throw XCTSkip("Explicit opt-in for read-only live OS validation")
        }
        let adapter = MacOSSystemApplyAdapter()
        let mappings = try adapter.readHIDMappings()
        XCTAssertEqual(try adapter.readHIDMappings(), mappings)
        print("Read-only live HID validation: common mapping count=\(mappings.count)")
    }

    func testDecodesNullKeyboardServiceTable() throws {
        let payload = """
        RegistryID  Key                   Value
        100000001   UserKeyMapping   (null)
        100000002   UserKeyMapping   (null)
        """
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(Data(payload.utf8)), [])
    }

    func testReadsKeyboardTableInsteadOfUnrelatedNullServices() throws {
        let global = """
        RegistryID  Key                   Value
        100000001   UserKeyMapping   (null)
        100000002   UserKeyMapping   (
          { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; }
        )
        """
        let keyboards = """
        RegistryID  Key                   Value
        100000002   UserKeyMapping   (
          { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; }
        )
        """
        let runner = FakeProcessRunner(outputs: [Data(global.utf8), Data(keyboards.utf8)])
        XCTAssertEqual(try MacOSSystemApplyAdapter(runner: runner).readHIDMappings(), [.tidyTapCapsLock])
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testDecodesTrimmedNullHIDPayloadAsEmptyMappings() throws {
        let payload = "\n  (null)  \t".data(using: .utf8)!

        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(payload), [])
    }

    func testRejectsEmptyAndInvalidHIDPayloads() {
        let payloads = [
            Data(),
            " \n\t ".data(using: .utf8)!,
            "[]".data(using: .utf8)!,
            "garbage".data(using: .utf8)!,
            "(NULL)".data(using: .utf8)!,
            "(null) trailing".data(using: .utf8)!
        ]

        for payload in payloads {
            XCTAssertThrowsError(try MacOSSystemApplyAdapter.decodeHIDMappings(payload)) {
                XCTAssertEqual($0 as? InputEngineError, .invalidSystemData(.hidMappings))
            }
        }
    }

    func testDecodesJSONAndOpenStepHIDPayloads() throws {
        let json = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]}
        """.data(using: .utf8)!
        let openStep = """
        ( { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; } )
        """.data(using: .utf8)!

        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(json), [.tidyTapCapsLock])
        XCTAssertEqual(try MacOSSystemApplyAdapter.decodeHIDMappings(openStep), [.tidyTapCapsLock])
    }

    func testApplyHIDUsesOnlyHIDUtilWithCompletePayload() throws {
        let runner = FakeProcessRunner(outputs: [Data("(null)".utf8)])
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        let unrelated = HIDMapping(source: 1, destination: 2)

        try adapter.applyHIDMappings([unrelated, .tidyTapCapsLock])

        XCTAssertEqual(runner.invocations.count, 2)
        XCTAssertEqual(runner.invocations[1].executable, "/usr/bin/hidutil")
        XCTAssertEqual(runner.invocations[1].arguments.prefix(2), ["property", "--set"])
        let payload = runner.invocations[1].arguments[2].data(using: .utf8)!
        XCTAssertEqual(
            try MacOSSystemApplyAdapter.decodeHIDMappings(payload),
            [unrelated, .tidyTapCapsLock]
        )
    }

    func testHotkeyDomainRoundTripsThroughDefaultsImport() throws {
        let domain: PropertyListDictionary = [
            "AppleSymbolicHotKeys": .dictionary([
                "60": .tidyTapHotkey60,
                "61": .dictionary(["enabled": .bool(false)])
            ]),
            "Other": .date(Date(timeIntervalSince1970: 10))
        ]
        let runner = FakeProcessRunner()
        let adapter = MacOSSystemApplyAdapter(runner: runner)

        try adapter.applySymbolicHotkeyDomain(domain)

        XCTAssertEqual(runner.invocations[0].executable, "/usr/bin/defaults")
        XCTAssertEqual(
            runner.invocations[0].arguments,
            ["import", MacOSSystemApplyAdapter.hotkeyDomain, "-"]
        )
        let imported = try PropertyListSerialization.propertyList(
            from: try XCTUnwrap(runner.invocations[0].input),
            format: nil
        ) as! [String: Any]
        let roundTripped = try imported.mapValues(PropertyListValue.init(any:))
        XCTAssertEqual(roundTripped, domain)
    }

    func testActivateSettingsUsesOnlyApprovedRefreshCommand() throws {
        let runner = FakeProcessRunner()
        let adapter = MacOSSystemApplyAdapter(runner: runner)

        try adapter.activateSymbolicHotkeySettings()

        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(
            runner.invocations[0].executable,
            MacOSSystemApplyAdapter.activateSettingsPath
        )
        XCTAssertEqual(runner.invocations[0].arguments, ["-u"])
    }
}
