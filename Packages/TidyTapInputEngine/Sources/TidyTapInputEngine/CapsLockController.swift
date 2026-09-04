import Foundation

public struct CapsHIDOwnership: Codable, Equatable, Sendable {
    public static let current = Self(version: 1)
    public let version: Int

    public init(version: Int) {
        self.version = version
    }
}

public struct HIDMappingChange: Equatable, Sendable {
    public let before: [HIDMapping]
    public let after: [HIDMapping]
    public let ownershipAfterCommit: CapsHIDOwnership?

    public init(
        before: [HIDMapping],
        after: [HIDMapping],
        ownershipAfterCommit: CapsHIDOwnership?
    ) {
        self.before = before
        self.after = after
        self.ownershipAfterCommit = ownershipAfterCommit
    }
}

public final class CapsLockController: @unchecked Sendable {
    private let system: any HIDMappingApplying

    public init(system: any HIDMappingApplying) {
        self.system = system
    }

    public func prepareEnable(
        existingOwnership: CapsHIDOwnership? = nil
    ) throws -> HIDMappingChange {
        let current = try system.readHIDMappings()
        let capsMappings = current.filter { $0.source == HIDMapping.capsLockSource }

        if let existingOwnership {
            guard existingOwnership == .current else {
                throw InputEngineError.capsLockOwnershipConflict
            }
            guard capsMappings == [.tidyTapCapsLock] else {
                throw InputEngineError.capsLockOwnershipConflict
            }
            return HIDMappingChange(
                before: current,
                after: current,
                ownershipAfterCommit: .current
            )
        }

        guard capsMappings.isEmpty else {
            throw InputEngineError.capsLockAlreadyMapped
        }
        return HIDMappingChange(
            before: current,
            after: current + [.tidyTapCapsLock],
            ownershipAfterCommit: .current
        )
    }

    public func prepareDisable(ownership: CapsHIDOwnership) throws -> HIDMappingChange {
        guard ownership == .current else {
            throw InputEngineError.capsLockOwnershipConflict
        }
        let current = try system.readHIDMappings()
        let ownedIndices = current.indices.filter { current[$0] == .tidyTapCapsLock }
        guard ownedIndices.count == 1 else {
            throw InputEngineError.capsLockOwnershipConflict
        }
        var after = current
        after.remove(at: ownedIndices[0])
        return HIDMappingChange(before: current, after: after, ownershipAfterCommit: nil)
    }

    public func commit(_ change: HIDMappingChange) throws {
        guard try system.readHIDMappings() == change.before else {
            throw InputEngineError.staleSystemState(.hidMappings)
        }
        guard change.before != change.after else { return }
        try system.applyHIDMappings(change.after)
        guard try system.readHIDMappings() == change.after else {
            throw InputEngineError.verificationFailed(.hidMappings)
        }
    }

    public func rollback(_ change: HIDMappingChange) throws {
        guard try system.readHIDMappings() == change.after else {
            throw InputEngineError.staleSystemState(.hidMappings)
        }
        guard change.before != change.after else { return }
        try system.applyHIDMappings(change.before)
        guard try system.readHIDMappings() == change.before else {
            throw InputEngineError.verificationFailed(.hidMappings)
        }
    }

    /// Roll back only when the live value is exactly the value this change installed.
    /// A value that is already `before` needs no work; every other value is an ownership conflict.
    public func rollbackIfApplied(_ change: HIDMappingChange) throws {
        let current = try system.readHIDMappings()
        if current == change.before { return }
        guard current == change.after else {
            throw InputEngineError.staleSystemState(.hidMappings)
        }
        try rollback(change)
    }
}

public struct Hotkey60Ownership: Codable, Equatable, Sendable {
    public let backup: PropertyListValue?
    public let hotkeysContainerExisted: Bool

    public init(backup: PropertyListValue?, hotkeysContainerExisted: Bool = true) {
        self.backup = backup
        self.hotkeysContainerExisted = hotkeysContainerExisted
    }
}

public struct Hotkey60Change: Equatable, Sendable {
    public let before: PropertyListDictionary
    public let after: PropertyListDictionary
    public let ownershipAfterCommit: Hotkey60Ownership?

    public init(
        before: PropertyListDictionary,
        after: PropertyListDictionary,
        ownershipAfterCommit: Hotkey60Ownership?
    ) {
        self.before = before
        self.after = after
        self.ownershipAfterCommit = ownershipAfterCommit
    }
}

public final class InputSourceShortcutController: @unchecked Sendable {
    public static let hotkeysKey = "AppleSymbolicHotKeys"
    public static let hotkey60Key = "60"

    private let system: any SymbolicHotkeyApplying

    public init(system: any SymbolicHotkeyApplying) {
        self.system = system
    }

    public func prepareEnable(
        existingOwnership: Hotkey60Ownership? = nil
    ) throws -> Hotkey60Change {
        let domain = try system.readSymbolicHotkeyDomain()
        let hotkeysContainerExisted = domain[Self.hotkeysKey] != nil
        let currentValue = try Self.checkedHotkey60(in: domain)

        if let existingOwnership {
            guard currentValue == .tidyTapHotkey60 else {
                throw InputEngineError.symbolicHotkeyOwnershipConflict
            }
            return Hotkey60Change(
                before: domain,
                after: domain,
                ownershipAfterCommit: existingOwnership
            )
        }

        guard currentValue != .tidyTapHotkey60 else {
            throw InputEngineError.symbolicHotkeyOwnershipConflict
        }
        let ownership = Hotkey60Ownership(
            backup: currentValue,
            hotkeysContainerExisted: hotkeysContainerExisted
        )
        let updated = Self.replacingHotkey60(in: domain, with: .tidyTapHotkey60)
        return Hotkey60Change(before: domain, after: updated, ownershipAfterCommit: ownership)
    }

    public func prepareDisable(ownership: Hotkey60Ownership) throws -> Hotkey60Change {
        let domain = try system.readSymbolicHotkeyDomain()
        guard try Self.checkedHotkey60(in: domain) == .tidyTapHotkey60 else {
            throw InputEngineError.symbolicHotkeyOwnershipConflict
        }
        var restored = Self.replacingHotkey60(in: domain, with: ownership.backup)
        if
            ownership.backup == nil,
            !ownership.hotkeysContainerExisted,
            case .dictionary(let hotkeys)? = restored[Self.hotkeysKey],
            hotkeys.isEmpty
        {
            restored.removeValue(forKey: Self.hotkeysKey)
        }
        return Hotkey60Change(
            before: domain,
            after: restored,
            ownershipAfterCommit: nil
        )
    }

    public func commit(_ change: Hotkey60Change) throws {
        guard try system.readSymbolicHotkeyDomain() == change.before else {
            throw InputEngineError.staleSystemState(.symbolicHotkey60)
        }
        guard change.before != change.after else { return }
        try system.applySymbolicHotkeyDomain(change.after)
        guard try system.readSymbolicHotkeyDomain() == change.after else {
            throw InputEngineError.verificationFailed(.symbolicHotkey60)
        }
        try system.activateSymbolicHotkeySettings()
    }

    public func rollback(_ change: Hotkey60Change) throws {
        guard try system.readSymbolicHotkeyDomain() == change.after else {
            throw InputEngineError.staleSystemState(.symbolicHotkey60)
        }
        guard change.before != change.after else { return }
        try system.applySymbolicHotkeyDomain(change.before)
        guard try system.readSymbolicHotkeyDomain() == change.before else {
            throw InputEngineError.verificationFailed(.symbolicHotkey60)
        }
        try system.activateSymbolicHotkeySettings()
    }

    /// Roll back only when hotkey 60 and the surrounding domain still match this change.
    public func rollbackIfApplied(_ change: Hotkey60Change) throws {
        let current = try system.readSymbolicHotkeyDomain()
        if current == change.before { return }
        guard current == change.after else {
            throw InputEngineError.staleSystemState(.symbolicHotkey60)
        }
        try rollback(change)
    }

    public static func hotkey60(in domain: PropertyListDictionary) -> PropertyListValue? {
        guard case .dictionary(let hotkeys)? = domain[hotkeysKey] else { return nil }
        return hotkeys[hotkey60Key]
    }

    private static func checkedHotkey60(
        in domain: PropertyListDictionary
    ) throws -> PropertyListValue? {
        guard let container = domain[hotkeysKey] else { return nil }
        guard case .dictionary(let hotkeys) = container else {
            throw InputEngineError.invalidSystemData(.symbolicHotkey60)
        }
        return hotkeys[hotkey60Key]
    }

    public static func replacingHotkey60(
        in domain: PropertyListDictionary,
        with replacement: PropertyListValue?
    ) -> PropertyListDictionary {
        var result = domain
        var hotkeys: PropertyListDictionary
        if case .dictionary(let current)? = result[hotkeysKey] {
            hotkeys = current
        } else {
            hotkeys = [:]
        }
        hotkeys[hotkey60Key] = replacement
        result[hotkeysKey] = .dictionary(hotkeys)
        return result
    }
}

public struct CapsLockFeatureOwnership: Codable, Equatable, Sendable {
    public let hid: CapsHIDOwnership
    public let hotkey60: Hotkey60Ownership

    public init(hid: CapsHIDOwnership, hotkey60: Hotkey60Ownership) {
        self.hid = hid
        self.hotkey60 = hotkey60
    }
}

public final class CapsLockFeatureController: @unchecked Sendable {
    private let hid: CapsLockController
    private let hotkey: InputSourceShortcutController

    public init(hid: CapsLockController, hotkey: InputSourceShortcutController) {
        self.hid = hid
        self.hotkey = hotkey
    }

    public func enable(
        existingOwnership: CapsLockFeatureOwnership? = nil
    ) throws -> CapsLockFeatureOwnership {
        let hidChange = try hid.prepareEnable(existingOwnership: existingOwnership?.hid)
        let hotkeyChange = try hotkey.prepareEnable(existingOwnership: existingOwnership?.hotkey60)
        do {
            try hid.commit(hidChange)
            do {
                try hotkey.commit(hotkeyChange)
            } catch {
                let rollbackIssues = rollbackIssues(for: [
                    (InputEngineComponent.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) }),
                    (InputEngineComponent.hidMappings, { try self.hid.rollbackIfApplied(hidChange) })
                ])
                throw TransactionFailure(
                    primaryDescription: String(describing: error),
                    rollbackIssues: rollbackIssues
                )
            }
        } catch let failure as TransactionFailure {
            throw failure
        } catch {
            let rollbackIssues = rollbackIssues(for: [
                (InputEngineComponent.hidMappings, { try self.hid.rollbackIfApplied(hidChange) })
            ])
            throw TransactionFailure(
                primaryDescription: String(describing: error),
                rollbackIssues: rollbackIssues
            )
        }

        guard
            let hidOwnership = hidChange.ownershipAfterCommit,
            let hotkeyOwnership = hotkeyChange.ownershipAfterCommit
        else {
            throw TransactionFailure(primaryDescription: "missing ownership after enable")
        }
        return CapsLockFeatureOwnership(hid: hidOwnership, hotkey60: hotkeyOwnership)
    }

    public func disable(ownership: CapsLockFeatureOwnership) throws {
        let hotkeyChange = try hotkey.prepareDisable(ownership: ownership.hotkey60)
        let hidChange = try hid.prepareDisable(ownership: ownership.hid)
        do {
            try hotkey.commit(hotkeyChange)
            do {
                try hid.commit(hidChange)
            } catch {
                let rollbackIssues = rollbackIssues(for: [
                    (InputEngineComponent.hidMappings, { try self.hid.rollbackIfApplied(hidChange) }),
                    (InputEngineComponent.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) })
                ])
                throw TransactionFailure(
                    primaryDescription: String(describing: error),
                    rollbackIssues: rollbackIssues
                )
            }
        } catch let failure as TransactionFailure {
            throw failure
        } catch {
            let rollbackIssues = rollbackIssues(for: [
                (InputEngineComponent.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) })
            ])
            throw TransactionFailure(
                primaryDescription: String(describing: error),
                rollbackIssues: rollbackIssues
            )
        }
    }

    private func rollbackIssues(
        for actions: [(InputEngineComponent, () throws -> Void)]
    ) -> [RollbackIssue] {
        actions.compactMap { component, action in
            do {
                try action()
                return nil
            } catch {
                return RollbackIssue(component: component, description: String(describing: error))
            }
        }
    }
}
