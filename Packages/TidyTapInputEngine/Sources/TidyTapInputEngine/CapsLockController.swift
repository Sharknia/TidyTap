import Foundation

public struct CapsHIDOwnership: Codable, Equatable, Sendable {
    public static let current = Self(version: 1)
    public let version: Int

    public init(version: Int) {
        self.version = version
    }
}

public struct HIDMappingChange: Codable, Equatable, Sendable {
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
            throw InputEngineError.preWriteStateChanged(.hidMappings)
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

    public func hasTidyTapMapping() throws -> Bool {
        try system.readHIDMappings().contains(.tidyTapCapsLock)
    }

    public func currentMappings() throws -> [HIDMapping] {
        try system.readHIDMappings()
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

public struct Hotkey60Change: Codable, Equatable, Sendable {
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
            throw InputEngineError.preWriteStateChanged(.symbolicHotkey60)
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

    public func hasTidyTapHotkey() throws -> Bool {
        try Self.checkedHotkey60(in: system.readSymbolicHotkeyDomain()) == .tidyTapHotkey60
    }

    public func currentDomain() throws -> PropertyListDictionary {
        try system.readSymbolicHotkeyDomain()
    }

    public func activateCurrentSettings() throws {
        try system.activateSymbolicHotkeySettings()
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

/// A durable, fully prepared transaction. Persisting both before/after values
/// lets a restarted helper distinguish an untouched transaction from each
/// partial commit without guessing from an ownership token alone.
public struct CapsLockEnablePlan: Codable, Equatable, Sendable {
    public let hid: HIDMappingChange
    public let hotkey60: Hotkey60Change

    public init(hid: HIDMappingChange, hotkey60: Hotkey60Change) {
        self.hid = hid
        self.hotkey60 = hotkey60
    }

    public var ownership: CapsLockFeatureOwnership? {
        guard let hidOwnership = hid.ownershipAfterCommit,
              let hotkeyOwnership = hotkey60.ownershipAfterCommit else {
            return nil
        }
        return CapsLockFeatureOwnership(hid: hidOwnership, hotkey60: hotkeyOwnership)
    }
}

public final class CapsLockFeatureController: @unchecked Sendable {
    private let hid: CapsLockController
    private let hotkey: InputSourceShortcutController
    private let inputSources: any InputSourceCounting

    public init(
        hid: CapsLockController,
        hotkey: InputSourceShortcutController,
        inputSources: any InputSourceCounting
    ) {
        self.hid = hid
        self.hotkey = hotkey
        self.inputSources = inputSources
    }

    public func enable(
        existingOwnership: CapsLockFeatureOwnership? = nil
    ) throws -> CapsLockFeatureOwnership {
        let inputSourceCount = try inputSources.enabledSelectableInputSourceCount()
        guard inputSourceCount == 2 else {
            throw InputEngineError.invalidInputSourceCount(inputSourceCount)
        }
        let hidChange = try hid.prepareEnable(existingOwnership: existingOwnership?.hid)
        let hotkeyChange = try hotkey.prepareEnable(existingOwnership: existingOwnership?.hotkey60)
        do {
            try hid.commit(hidChange)
            do {
                try hotkey.commit(hotkeyChange)
            } catch {
                var actions: [(InputEngineComponent, () throws -> Void)] = []
                if !Self.isPreWriteRejection(error, for: .symbolicHotkey60) {
                    actions.append((.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) }))
                }
                actions.append((.hidMappings, { try self.hid.rollbackIfApplied(hidChange) }))
                let rollbackIssues = rollbackIssues(for: actions)
                throw TransactionFailure(
                    primaryDescription: String(describing: error),
                    rollbackIssues: rollbackIssues
                )
            }
        } catch let failure as TransactionFailure {
            throw failure
        } catch {
            let actions: [(InputEngineComponent, () throws -> Void)] =
                Self.isPreWriteRejection(error, for: .hidMappings)
                ? []
                : [(.hidMappings, { try self.hid.rollbackIfApplied(hidChange) })]
            let rollbackIssues = rollbackIssues(for: actions)
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

    public func prepareEnablePlan() throws -> CapsLockEnablePlan {
        let inputSourceCount = try inputSources.enabledSelectableInputSourceCount()
        guard inputSourceCount == 2 else {
            throw InputEngineError.invalidInputSourceCount(inputSourceCount)
        }
        return CapsLockEnablePlan(
            hid: try hid.prepareEnable(),
            hotkey60: try hotkey.prepareEnable()
        )
    }

    /// Completes a previously persisted plan. Each component must still equal
    /// either its exact before or after value; unrelated live changes are
    /// never overwritten. Hotkey activation is repeated when its plist write
    /// survived because a crash may have happened before activation.
    public func completePreparedEnable(_ plan: CapsLockEnablePlan) throws -> CapsLockFeatureOwnership {
        guard let ownership = plan.ownership else {
            throw TransactionFailure(primaryDescription: "missing ownership in prepared enable")
        }

        var hidWasApplied = false
        let liveHID = try hid.currentMappings()
        if liveHID == plan.hid.before {
            try hid.commit(plan.hid)
            hidWasApplied = true
        } else if liveHID != plan.hid.after {
            throw InputEngineError.staleSystemState(.hidMappings)
        }

        do {
            let liveHotkey = try hotkey.currentDomain()
            if liveHotkey == plan.hotkey60.before {
                try hotkey.commit(plan.hotkey60)
            } else if liveHotkey == plan.hotkey60.after {
                try hotkey.activateCurrentSettings()
            } else {
                throw InputEngineError.staleSystemState(.symbolicHotkey60)
            }
        } catch {
            let issues = hidWasApplied
                ? rollbackIssues(for: [
                    (.hidMappings, { try self.hid.rollbackIfApplied(plan.hid) })
                ])
                : []
            if issues.isEmpty, let engineError = error as? InputEngineError {
                throw engineError
            }
            throw TransactionFailure(
                primaryDescription: String(describing: error),
                rollbackIssues: issues
            )
        }
        return ownership
    }

    /// Reboots clear hidutil's volatile mapping while the symbolic hotkey and
    /// durable ownership survive. Only that exact state is repaired.
    public func recoverHIDAfterReset(ownership: CapsLockFeatureOwnership) throws {
        _ = ownership
        let inputSourceCount = try inputSources.enabledSelectableInputSourceCount()
        guard inputSourceCount == 2 else {
            throw InputEngineError.invalidInputSourceCount(inputSourceCount)
        }
        guard try hotkey.hasTidyTapHotkey() else {
            throw InputEngineError.symbolicHotkeyOwnershipConflict
        }
        try hid.commit(hid.prepareEnable())
    }

    /// Computes the durable ownership record without changing the system.
    public func prepareOwnershipForEnable() throws -> CapsLockFeatureOwnership {
        guard let ownership = try prepareEnablePlan().ownership else {
            throw TransactionFailure(primaryDescription: "missing ownership after prepare")
        }
        return ownership
    }

    public func isApplied(_ ownership: CapsLockFeatureOwnership) throws -> Bool {
        _ = ownership
        return try hid.hasTidyTapMapping() && hotkey.hasTidyTapHotkey()
    }

    public func disable(ownership: CapsLockFeatureOwnership) throws {
        let hotkeyChange = try hotkey.hasTidyTapHotkey()
            ? hotkey.prepareDisable(ownership: ownership.hotkey60) : nil
        let hidChange = try hid.hasTidyTapMapping()
            ? hid.prepareDisable(ownership: ownership.hid) : nil
        guard hotkeyChange != nil || hidChange != nil else { return }
        do {
            if let hotkeyChange { try hotkey.commit(hotkeyChange) }
            do {
                if let hidChange { try hid.commit(hidChange) }
            } catch {
                var actions: [(InputEngineComponent, () throws -> Void)] = []
                if let hidChange, !Self.isPreWriteRejection(error, for: .hidMappings) {
                    actions.append((.hidMappings, { try self.hid.rollbackIfApplied(hidChange) }))
                }
                if let hotkeyChange { actions.append((.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) })) }
                let rollbackIssues = rollbackIssues(for: actions)
                throw TransactionFailure(
                    primaryDescription: String(describing: error),
                    rollbackIssues: rollbackIssues
                )
            }
        } catch let failure as TransactionFailure {
            throw failure
        } catch {
            var actions: [(InputEngineComponent, () throws -> Void)] = []
            if let hotkeyChange, !Self.isPreWriteRejection(error, for: .symbolicHotkey60) {
                actions.append((.symbolicHotkey60, { try self.hotkey.rollbackIfApplied(hotkeyChange) }))
            }
            let rollbackIssues = rollbackIssues(for: actions)
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

    private static func isPreWriteRejection(
        _ error: Error,
        for component: InputEngineComponent
    ) -> Bool {
        (error as? InputEngineError) == .preWriteStateChanged(component)
    }
}
