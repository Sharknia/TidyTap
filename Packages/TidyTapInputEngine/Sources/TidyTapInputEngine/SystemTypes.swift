import Foundation

public enum InputEngineComponent: String, Equatable, Sendable {
    case inputSources
    case hidMappings
    case symbolicHotkey60
    case eventTap
}

public enum InputEngineError: Error, Equatable, Sendable {
    case capsLockAlreadyMapped
    case capsLockOwnershipConflict
    case symbolicHotkeyOwnershipConflict
    case invalidInputSourceCount(Int)
    case preWriteStateChanged(InputEngineComponent)
    case staleSystemState(InputEngineComponent)
    case verificationFailed(InputEngineComponent)
    case invalidSystemData(InputEngineComponent)
    case commandFailed(executable: String, status: Int32, detail: String)
    case eventTapCreationFailed
    case eventTapRecoveryFailed
}

public struct RollbackIssue: Error, Equatable, Sendable {
    public let component: InputEngineComponent
    public let description: String

    public init(component: InputEngineComponent, description: String) {
        self.component = component
        self.description = description
    }
}

public struct TransactionFailure: Error, Equatable, Sendable {
    public let primaryDescription: String
    public let rollbackIssues: [RollbackIssue]

    public init(primaryDescription: String, rollbackIssues: [RollbackIssue] = []) {
        self.primaryDescription = primaryDescription
        self.rollbackIssues = rollbackIssues
    }

    public var recoveryRequired: Bool { !rollbackIssues.isEmpty }
}

public struct HIDMapping: Codable, Equatable, Hashable, Sendable {
    public static let capsLockSource: UInt64 = 0x700000039
    public static let f18Destination: UInt64 = 0x70000006d
    public static let tidyTapCapsLock = HIDMapping(
        source: capsLockSource,
        destination: f18Destination
    )

    public let source: UInt64
    public let destination: UInt64

    public init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }

    init?(hidDictionary: [String: Any]) {
        guard
            let source = Self.number(hidDictionary["HIDKeyboardModifierMappingSrc"]),
            let destination = Self.number(hidDictionary["HIDKeyboardModifierMappingDst"])
        else {
            return nil
        }
        self.init(source: source, destination: destination)
    }

    var hidDictionary: [String: UInt64] {
        [
            "HIDKeyboardModifierMappingSrc": source,
            "HIDKeyboardModifierMappingDst": destination
        ]
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return UInt64(exactly: value) }
        if let value = value as? String { return UInt64(value) }
        return nil
    }
}

public indirect enum PropertyListValue: Codable, Equatable, Sendable {
    case dictionary([String: PropertyListValue])
    case array([PropertyListValue])
    case string(String)
    case integer(Int64)
    case real(Double)
    case bool(Bool)
    case data(Data)
    case date(Date)

    init(any value: Any) throws {
        switch value {
        case let value as [String: Any]:
            self = .dictionary(try value.mapValues(Self.init(any:)))
        case let value as [Any]:
            self = .array(try value.map(Self.init(any:)))
        case let value as String:
            self = .string(value)
        case let value as Data:
            self = .data(value)
        case let value as Date:
            self = .date(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .real(value.doubleValue)
            } else {
                self = .integer(value.int64Value)
            }
        default:
            throw InputEngineError.invalidSystemData(.symbolicHotkey60)
        }
    }

    var anyValue: Any {
        switch self {
        case .dictionary(let value): value.mapValues(\.anyValue)
        case .array(let value): value.map(\.anyValue)
        case .string(let value): value
        case .integer(let value): NSNumber(value: value)
        case .real(let value): NSNumber(value: value)
        case .bool(let value): NSNumber(value: value)
        case .data(let value): value
        case .date(let value): value
        }
    }
}

public typealias PropertyListDictionary = [String: PropertyListValue]

public extension PropertyListValue {
    static let tidyTapHotkey60: Self = .dictionary([
        "enabled": .bool(true),
        "value": .dictionary([
            "parameters": .array([.integer(65_535), .integer(79), .integer(8_388_608)]),
            "type": .string("standard")
        ])
    ])
}

public protocol HIDMappingApplying: Sendable {
    func readHIDMappings() throws -> [HIDMapping]
    func applyHIDMappings(_ mappings: [HIDMapping]) throws
}

public protocol SymbolicHotkeyApplying: Sendable {
    func readSymbolicHotkeyDomain() throws -> PropertyListDictionary
    func applySymbolicHotkeyDomain(_ domain: PropertyListDictionary) throws
    func activateSymbolicHotkeySettings() throws
}

public protocol InputSourceCounting: Sendable {
    func enabledSelectableInputSourceCount() throws -> Int
}
