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

    init(outputs: [Data] = []) {
        self.outputs = outputs
    }

    func run(executable: String, arguments: [String], input: Data?) throws -> Data {
        invocations.append(.init(executable: executable, arguments: arguments, input: input))
        return outputs.isEmpty ? Data() : outputs.removeFirst()
    }
}

final class SystemApplyAdapterTests: XCTestCase {
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
        let runner = FakeProcessRunner()
        let adapter = MacOSSystemApplyAdapter(runner: runner)
        let unrelated = HIDMapping(source: 1, destination: 2)

        try adapter.applyHIDMappings([unrelated, .tidyTapCapsLock])

        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations[0].executable, "/usr/bin/hidutil")
        XCTAssertEqual(runner.invocations[0].arguments.prefix(2), ["property", "--set"])
        let payload = runner.invocations[0].arguments[2].data(using: .utf8)!
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
