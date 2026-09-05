import Foundation

public enum ProbeError: Error, LocalizedError, Equatable {
    case capsLockOwnedByAnotherMapping
    case symbolicHotkeyChanged
    case hidMappingsChanged
    case invalidPreferences
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .capsLockOwnedByAnotherMapping: "Caps Lock already has a non-TidyTap mapping. Refusing to overwrite it."
        case .symbolicHotkeyChanged: "Symbolic hotkey 60 changed after activation. Refusing to overwrite it."
        case .hidMappingsChanged: "HID mappings changed after inspection. Refusing to overwrite them."
        case .invalidPreferences: "The symbolic hotkey preferences could not be decoded."
        case .commandFailed(let message): message
        }
    }
}

public struct HIDMapping: Codable, Equatable, Hashable, Sendable {
    public static let capsLockSource: UInt64 = 0x700000039
    public static let f18Destination: UInt64 = 0x70000006d
    public let source: UInt64
    public let destination: UInt64

    public init(source: UInt64, destination: UInt64) { self.source = source; self.destination = destination }
    public static var tidyTapCapsLock: HIDMapping { HIDMapping(source: capsLockSource, destination: f18Destination) }

    public init?(hidDictionary: [String: Any]) {
        guard let source = Self.number(hidDictionary["HIDKeyboardModifierMappingSrc"]),
              let destination = Self.number(hidDictionary["HIDKeyboardModifierMappingDst"]) else { return nil }
        self.init(source: source, destination: destination)
    }

    public var hidDictionary: [String: UInt64] {
        ["HIDKeyboardModifierMappingSrc": source, "HIDKeyboardModifierMappingDst": destination]
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return UInt64(exactly: value) }
        if let value = value as? String { return UInt64(value) }
        return nil
    }
}

public enum HIDMappingMerger {
    /// Adds only TidyTap's pair. Any other Caps Lock source is an ownership conflict.
    public static func apply(to current: [HIDMapping]) throws -> [HIDMapping] {
        let capsMappings = current.filter { $0.source == HIDMapping.capsLockSource }
        guard capsMappings.allSatisfy({ $0 == HIDMapping.tidyTapCapsLock }) else { throw ProbeError.capsLockOwnedByAnotherMapping }
        if !capsMappings.isEmpty { return current }
        return current + [.tidyTapCapsLock]
    }

    /// Removes exactly TidyTap's pair; all unrelated mappings, including other Caps Lock pairs, remain intact.
    public static func removeTidyTap(from current: [HIDMapping]) -> [HIDMapping] {
        current.filter { $0 != .tidyTapCapsLock }
    }
}

public enum SymbolicHotkey60 {
    public static let identifier = "60"
    // Carbon virtual keycode 79 is F18. 0x00800000 is the secondary-Fn modifier mask
    // observed in the supported macOS 26.6.2 target's System Settings F18 binding.
    public static func tidyTapValue() -> [String: Any] {
        ["enabled": true, "value": ["parameters": [65535, 79, 8_388_608], "type": "standard"]]
    }

    public static func apply(to hotkeys: [String: Any]) -> [String: Any] {
        var copy = hotkeys
        copy[identifier] = tidyTapValue()
        return copy
    }

    /// Restores a backup only if the present entry is still the entry this probe installed.
    public static func restore(current: [String: Any], backup: Any?) throws -> [String: Any] {
        guard plistEqual(current[identifier], tidyTapValue()) else { throw ProbeError.symbolicHotkeyChanged }
        var copy = current
        if let backup { copy[identifier] = backup } else { copy.removeValue(forKey: identifier) }
        return copy
    }

    public static func plistEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return (lhs as AnyObject).isEqual(rhs)
    }
}

public struct ProbeSnapshot {
    public let mappings: [HIDMapping]
    public let hotkeys: [String: Any]
    public init(mappings: [HIDMapping], hotkeys: [String: Any]) { self.mappings = mappings; self.hotkeys = hotkeys }
}

public enum CommandRunner {
    @discardableResult public static func run(_ executable: String, _ arguments: [String], input: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe(); let stderr = Pipe(); process.standardOutput = stdout; process.standardError = stderr
        let stdin = input.map { _ in Pipe() }; process.standardInput = stdin
        try process.run()
        let group = DispatchGroup(); let output = DataCollector(); let errorOutput = DataCollector()
        group.enter(); DispatchQueue.global().async { output.set(stdout.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter(); DispatchQueue.global().async { errorOutput.set(stderr.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        if let input, let stdin { stdin.fileHandleForWriting.write(input); stdin.fileHandleForWriting.closeFile() }
        process.waitUntilExit(); group.wait()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorOutput.get(), encoding: .utf8) ?? "unknown error"
            throw ProbeError.commandFailed("\(executable) failed: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output.get()
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data()
    func set(_ newValue: Data) { lock.lock(); defer { lock.unlock() }; data = newValue }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

public enum SystemProbe {
    public static func inspect() throws -> ProbeSnapshot {
        let hidData = try CommandRunner.run("/usr/bin/hidutil", ["property", "--get", "UserKeyMapping"])
        let mappings = try decodeHIDMappings(hidData)
        let defaultsData = try CommandRunner.run("/usr/bin/defaults", ["export", "com.apple.symbolichotkeys", "-"])
        let defaults = try PropertyListSerialization.propertyList(from: defaultsData, format: nil) as? [String: Any]
        guard let defaults else { throw ProbeError.invalidPreferences }
        return ProbeSnapshot(mappings: mappings, hotkeys: defaults["AppleSymbolicHotKeys"] as? [String: Any] ?? [:])
    }

    /// Explicit mutation path. Callers must obtain and persist backups before calling this function.
    public static func apply(snapshot: ProbeSnapshot) throws {
        let live = try inspect()
        guard live.mappings == snapshot.mappings else { throw ProbeError.hidMappingsChanged }
        let mappings = try HIDMappingMerger.apply(to: live.mappings)
        let mappingData = try hidutilPayload(mappings)
        try replaceHotkey60(expected: snapshot.hotkeys[SymbolicHotkey60.identifier], with: SymbolicHotkey60.tidyTapValue())
        do {
            // `hidutil --set` replaces the complete property. Re-read immediately before it;
            // any intervening third-party change is a conflict, never a blind overwrite.
            guard try inspect().mappings == snapshot.mappings else { throw ProbeError.hidMappingsChanged }
            _ = try CommandRunner.run("/usr/bin/hidutil", ["property", "--set", String(data: mappingData, encoding: .utf8)!])
        } catch {
            // A failed second step must not leave the shortcut claimed by TidyTap.
            try? replaceHotkey60(expected: SymbolicHotkey60.tidyTapValue(), with: snapshot.hotkeys[SymbolicHotkey60.identifier])
            throw error
        }
    }

    public static func restore(snapshot: ProbeSnapshot, current: ProbeSnapshot) throws {
        let live = try inspect()
        guard live.mappings == current.mappings else { throw ProbeError.hidMappingsChanged }
        let mappings = HIDMappingMerger.removeTidyTap(from: live.mappings)
        let mappingData = try hidutilPayload(mappings)
        _ = try SymbolicHotkey60.restore(current: current.hotkeys, backup: snapshot.hotkeys[SymbolicHotkey60.identifier])
        try replaceHotkey60(expected: SymbolicHotkey60.tidyTapValue(), with: snapshot.hotkeys[SymbolicHotkey60.identifier])
        do {
            guard try inspect().mappings == current.mappings else { throw ProbeError.hidMappingsChanged }
            _ = try CommandRunner.run("/usr/bin/hidutil", ["property", "--set", String(data: mappingData, encoding: .utf8)!])
        } catch {
            try? replaceHotkey60(expected: snapshot.hotkeys[SymbolicHotkey60.identifier], with: SymbolicHotkey60.tidyTapValue())
            throw error
        }
    }

    private static func replaceHotkey60(expected: Any?, with replacement: Any?) throws {
        // Merge into a fresh whole-domain export, preserving every domain key. This is deliberately
        // inaccessible from the CLI; production integration must add an optimistic re-read before it.
        let existingData = try CommandRunner.run("/usr/bin/defaults", ["export", "com.apple.symbolichotkeys", "-"])
        var domain = try PropertyListSerialization.propertyList(from: existingData, format: nil) as? [String: Any] ?? [:]
        var hotkeys = domain["AppleSymbolicHotKeys"] as? [String: Any] ?? [:]
        guard SymbolicHotkey60.plistEqual(hotkeys[SymbolicHotkey60.identifier], expected) else {
            throw ProbeError.symbolicHotkeyChanged
        }
        if let replacement { hotkeys[SymbolicHotkey60.identifier] = replacement }
        else { hotkeys.removeValue(forKey: SymbolicHotkey60.identifier) }
        domain["AppleSymbolicHotKeys"] = hotkeys
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
        _ = try CommandRunner.run("/usr/bin/defaults", ["import", "com.apple.symbolichotkeys", "-"], input: data)
    }

    private static func hidutilPayload(_ mappings: [HIDMapping]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings.map(\.hidDictionary)])
    }

    static func decodeHIDMappings(_ data: Data) throws -> [HIDMapping] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mappings = json["UserKeyMapping"] as? [[String: Any]] {
            return try decodeMappings(mappings)
        }
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let rawMappings: [[String: Any]]
        if let array = object as? [[String: Any]] { rawMappings = array }
        else if let dictionary = object as? [String: Any], let array = dictionary["UserKeyMapping"] as? [[String: Any]] { rawMappings = array }
        else { throw ProbeError.invalidPreferences }
        return try decodeMappings(rawMappings)
    }

    private static func decodeMappings(_ rawMappings: [[String: Any]]) throws -> [HIDMapping] {
        let mappings = rawMappings.compactMap(HIDMapping.init(hidDictionary:))
        guard mappings.count == rawMappings.count else { throw ProbeError.invalidPreferences }
        return mappings
    }
}
