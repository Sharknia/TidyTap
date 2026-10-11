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
    private enum HIDScope {
        case legacy
        case keyboards

        var arguments: [String] {
            switch self {
            case .legacy: []
            case .keyboards: ["--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"]
            }
        }
    }
    // Scope discovery and HID commands are serialized. Once selected, scope
    // stays fixed across pre-write checks, verification and rollback.
    private let hidLock = NSLock()
    private var hidScope: HIDScope?
    private var hasValidatedHIDRead = false

    public init(runner: any ProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    public func readHIDMappings() throws -> [HIDMapping] {
        hidLock.lock()
        defer { hidLock.unlock() }
        return try readHIDMappingsLocked()
    }

    private func readHIDMappingsLocked() throws -> [HIDMapping] {
        hasValidatedHIDRead = false
        var data: Data
        if let hidScope {
            data = try readHIDProperty(scope: hidScope)
        } else {
            data = try readHIDProperty(scope: .legacy)
            if Self.hasHIDTableHeader(data) {
                hidScope = .keyboards
                data = try readHIDProperty(scope: .keyboards)
            } else {
                hidScope = .legacy
            }
        }
        // Do not silently broaden writes if the output changes or a matched
        // query fails. Legacy systems retain their original command path.
        guard Self.hasHIDTableHeader(data) == (hidScope == .keyboards) else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        let mappings = try Self.decodeHIDMappings(data)
        hasValidatedHIDRead = true
        return mappings
    }

    private func readHIDProperty(scope: HIDScope) throws -> Data {
        try runner.run(
            executable: "/usr/bin/hidutil",
            arguments: ["property"] + scope.arguments + ["--get", "UserKeyMapping"],
            input: nil
        )
    }

    public func applyHIDMappings(_ mappings: [HIDMapping]) throws {
        hidLock.lock()
        defer { hidLock.unlock() }
        if !hasValidatedHIDRead { _ = try readHIDMappingsLocked() }
        guard let hidScope else { throw InputEngineError.invalidSystemData(.hidMappings) }
        let data = try JSONSerialization.data(
            withJSONObject: ["UserKeyMapping": mappings.map(\.hidDictionary)]
        )
        guard let payload = String(data: data, encoding: .utf8) else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        hasValidatedHIDRead = false
        _ = try runner.run(
            executable: "/usr/bin/hidutil",
            arguments: ["property"] + hidScope.arguments + ["--set", payload],
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
        if hasHIDTableHeader(data) { return try decodeHIDTable(data) }
        return try decodeLegacyHIDMappings(data)
    }

    private static func hasHIDTableHeader(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first?
            .split(whereSeparator: { $0.isWhitespace }).map(String.init) == ["RegistryID", "Key", "Value"]
    }

    private static func decodeHIDTable(_ data: Data) throws -> [HIDMapping] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let body = lines.dropFirst().joined(separator: "\n") as NSString
        let row = try NSRegularExpression(pattern: "(?m)^[ \\t]*([0-9a-fA-F]+)[ \\t]+([A-Za-z][A-Za-z0-9_]*)[ \\t]+")
        let rows = row.matches(in: body as String, range: NSRange(location: 0, length: body.length))
        guard let first = rows.first,
              body.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        var identifiers = Set<UInt64>()
        var consensus: [HIDMapping]?
        for (index, match) in rows.enumerated() {
            guard let identifier = UInt64(body.substring(with: match.range(at: 1)), radix: 16),
                  identifiers.insert(identifier).inserted,
                  body.substring(with: match.range(at: 2)) == "UserKeyMapping" else {
                throw InputEngineError.invalidSystemData(.hidMappings)
            }
            let start = NSMaxRange(match.range)
            let end = index + 1 < rows.count ? rows[index + 1].range.location : body.length
            let value = body.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let mappings: [HIDMapping]
            if value == "(null)" {
                mappings = []
            } else {
                try validateTableArray(value)
                mappings = try decodeLegacyHIDMappings(Data(value.utf8))
            }
            if let consensus, consensus != mappings {
                // A single global backup cannot represent per-device states.
                throw InputEngineError.invalidSystemData(.hidMappings)
            }
            consensus = mappings
        }
        return consensus ?? []
    }

    private static func validateTableArray(_ value: String) throws {
        guard value.first == "(", value.last == ")" else {
            throw InputEngineError.invalidSystemData(.hidMappings)
        }
        // OpenStep parsers may ignore trailing input. Require exactly one
        // complete array, accounting for quoted/escaped string values.
        var depth = 0
        var quoted = false
        var escaped = false
        for index in value.indices {
            let character = value[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                guard depth >= 0, depth != 0 || index == value.index(before: value.endIndex) else {
                    throw InputEngineError.invalidSystemData(.hidMappings)
                }
            }
        }
        guard depth == 0, !quoted else { throw InputEngineError.invalidSystemData(.hidMappings) }
    }

    private static func decodeLegacyHIDMappings(_ data: Data) throws -> [HIDMapping] {
        if String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "(null)"
        {
            return []
        }

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
