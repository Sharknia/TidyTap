import Carbon
import Foundation

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], input: Data?) throws -> Data
}

public final class FoundationProcessRunner: ProcessRunning, @unchecked Sendable {
    public init() {}

    public func run(executable: String, arguments: [String], input: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = input.map { _ in Pipe() }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()

        let group = DispatchGroup()
        let output = LockedData()
        let errorOutput = LockedData()
        group.enter()
        DispatchQueue.global().async {
            output.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errorOutput.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        group.wait()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorOutput.get(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw InputEngineError.commandFailed(
                executable: executable,
                status: process.terminationStatus,
                detail: detail
            )
        }
        return output.get()
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ value: Data) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Production adapter for the narrow, stage-0-validated command-line system surface.
/// It never invokes IOHID APIs and always writes complete freshly prepared payloads.
public final class MacOSSystemApplyAdapter: HIDMappingApplying, SymbolicHotkeyApplying, InputSourceCounting, @unchecked Sendable {
    public static let hotkeyDomain = "com.apple.symbolichotkeys"
    public static let activateSettingsPath =
        "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    public func readHIDMappings() throws -> [HIDMapping] {
        let data = try runner.run(
            executable: "/usr/bin/hidutil",
            arguments: ["property", "--get", "UserKeyMapping"],
            input: nil
        )
        return try Self.decodeHIDMappings(data)
    }

    public func applyHIDMappings(_ mappings: [HIDMapping]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["UserKeyMapping": mappings.map(\.hidDictionary)]
        )
        guard let payload = String(data: data, encoding: .utf8) else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        _ = try runner.run(
            executable: "/usr/bin/hidutil",
            arguments: ["property", "--set", payload],
            input: nil
        )
    }

    public func readSymbolicHotkeyDomain() throws -> PropertyListDictionary {
        let data = try runner.run(
            executable: "/usr/bin/defaults",
            arguments: ["export", Self.hotkeyDomain, "-"],
            input: nil
        )
        guard let raw = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InputEngineError.invalidSystemData(.symbolicHotkey60)
        }
        do {
            return try raw.mapValues(PropertyListValue.init(any:))
        } catch {
            throw InputEngineError.invalidSystemData(.symbolicHotkey60)
        }
    }

    public func applySymbolicHotkeyDomain(_ domain: PropertyListDictionary) throws {
        let raw = domain.mapValues(\.anyValue)
        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: raw,
                format: .xml,
                options: 0
            )
        } catch {
            throw InputEngineError.invalidSystemData(.symbolicHotkey60)
        }
        _ = try runner.run(
            executable: "/usr/bin/defaults",
            arguments: ["import", Self.hotkeyDomain, "-"],
            input: data
        )
    }

    public func activateSymbolicHotkeySettings() throws {
        _ = try runner.run(
            executable: Self.activateSettingsPath,
            arguments: ["-u"],
            input: nil
        )
    }

    public func enabledSelectableInputSourceCount() throws -> Int {
        let properties: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        guard let sources = TISCreateInputSourceList(properties as CFDictionary, false) else {
            throw InputEngineError.invalidSystemData(.inputSources)
        }
        return CFArrayGetCount(sources.takeRetainedValue())
    }

    static func decodeHIDMappings(_ data: Data) throws -> [HIDMapping] {
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let mappings = json["UserKeyMapping"] as? [[String: Any]]
        {
            return try decodeMappings(mappings)
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        let mappings: [[String: Any]]
        if let array = object as? [[String: Any]] {
            mappings = array
        } else if
            let dictionary = object as? [String: Any],
            let array = dictionary["UserKeyMapping"] as? [[String: Any]]
        {
            mappings = array
        } else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        return try decodeMappings(mappings)
    }

    private static func decodeMappings(_ raw: [[String: Any]]) throws -> [HIDMapping] {
        let mappings = raw.compactMap(HIDMapping.init(hidDictionary:))
        guard mappings.count == raw.count else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        return mappings
    }
}
