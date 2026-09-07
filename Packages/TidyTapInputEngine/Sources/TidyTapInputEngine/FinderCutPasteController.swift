import Foundation

struct FinderContext: Equatable, Sendable {
    let processIdentifier: Int32
    let windowIdentifier: UInt
}

struct FinderPasteboardSnapshot: Equatable, Sendable {
    let changeCount: Int
    let containsFiles: Bool
}

protocol FinderCutPasteEnvironment: Sendable {
    func focusedFileListContext() -> FinderContext?
    func pasteboardSnapshot() -> FinderPasteboardSnapshot
    func sendDeferredMove() -> Bool
}

enum FinderKeyDisposition: Equatable {
    case passThrough
    case consume
    case replaceWithCopy
    case replaceWithMove
}

final class FinderCutPasteController: @unchecked Sendable {
    private struct PendingCopy {
        let generation: UInt64
        let baselineChangeCount: Int
        let context: FinderContext
        var registrationAllowed: Bool
        var deferredPaste: Bool
    }

    private let environment: any FinderCutPasteEnvironment
    private let queue: DispatchQueue
    private let pollingInterval: TimeInterval
    private let pollingAttempts: Int
    private let lock = NSLock()
    private var enabled = false
    private var generation: UInt64 = 0
    private var pending: PendingCopy?
    private var armedChangeCount: Int?
    private var transformedCopyKeyIsDown = false
    private var transformedMoveKeyIsDown = false
    private var consumedCopyKeyIsDown = false
    private var consumedPasteKeyIsDown = false

    init(
        environment: any FinderCutPasteEnvironment,
        queue: DispatchQueue? = nil,
        pollingInterval: TimeInterval = 0.02,
        pollingAttempts: Int = 25
    ) {
        self.environment = environment
        self.queue = queue ?? DispatchQueue(
            label: "com.tidytap.finder-cut-paste",
            qos: .userInitiated
        )
        self.pollingInterval = pollingInterval
        self.pollingAttempts = pollingAttempts
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        resetStateLocked()
        lock.unlock()
    }

    func resetAfterTapDisable() {
        lock.lock()
        resetStateLocked()
        lock.unlock()
    }

    private func resetStateLocked() {
        generation &+= 1
        pending = nil
        armedChangeCount = nil
        transformedCopyKeyIsDown = false
        transformedMoveKeyIsDown = false
        consumedCopyKeyIsDown = false
        consumedPasteKeyIsDown = false
    }

    func handle(keyCode: Int64, isDown: Bool, isRepeat: Bool) -> FinderKeyDisposition {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return .passThrough }

        if keyCode == Self.xKeyCode {
            return handleX(isDown: isDown, isRepeat: isRepeat)
        }
        if keyCode == Self.cKeyCode {
            if isDown && !isRepeat { invalidatePendingAndArmed() }
            return .passThrough
        }
        if keyCode == Self.vKeyCode {
            return handleV(isDown: isDown, isRepeat: isRepeat)
        }
        return .passThrough
    }

    private func handleX(isDown: Bool, isRepeat: Bool) -> FinderKeyDisposition {
        if !isDown {
            if transformedCopyKeyIsDown {
                transformedCopyKeyIsDown = false
                return .replaceWithCopy
            }
            if consumedCopyKeyIsDown {
                consumedCopyKeyIsDown = false
                return .consume
            }
            return .passThrough
        }
        if isRepeat {
            return (transformedCopyKeyIsDown || consumedCopyKeyIsDown) ? .consume : .passThrough
        }
        guard let context = environment.focusedFileListContext() else {
            invalidatePendingAndArmed()
            return .passThrough
        }
        guard pending == nil else {
            consumedCopyKeyIsDown = true
            return .consume
        }

        generation &+= 1
        let requestGeneration = generation
        let baseline = environment.pasteboardSnapshot().changeCount
        armedChangeCount = nil
        pending = PendingCopy(
            generation: requestGeneration,
            baselineChangeCount: baseline,
            context: context,
            registrationAllowed: true,
            deferredPaste: false
        )
        transformedCopyKeyIsDown = true
        schedulePoll(generation: requestGeneration, attempt: 0)
        return .replaceWithCopy
    }

    private func handleV(isDown: Bool, isRepeat: Bool) -> FinderKeyDisposition {
        if !isDown {
            if transformedMoveKeyIsDown {
                transformedMoveKeyIsDown = false
                return .replaceWithMove
            }
            if consumedPasteKeyIsDown {
                consumedPasteKeyIsDown = false
                return .consume
            }
            return .passThrough
        }
        if isRepeat {
            return (transformedMoveKeyIsDown || consumedPasteKeyIsDown) ? .consume : .passThrough
        }

        if var pending {
            guard pending.registrationAllowed else {
                invalidatePendingAndArmed()
                return .passThrough
            }
            guard let currentContext = environment.focusedFileListContext() else {
                invalidatePendingAndArmed()
                return .passThrough
            }
            guard currentContext == pending.context else {
                invalidatePendingAndArmed()
                consumedPasteKeyIsDown = true
                return .consume
            }
            pending.deferredPaste = true
            self.pending = pending
            consumedPasteKeyIsDown = true
            return .consume
        }

        guard let armedChangeCount,
              environment.focusedFileListContext() != nil else {
            return .passThrough
        }
        let snapshot = environment.pasteboardSnapshot()
        guard snapshot.changeCount == armedChangeCount else {
            self.armedChangeCount = nil
            return .passThrough
        }
        self.armedChangeCount = nil
        transformedMoveKeyIsDown = true
        return .replaceWithMove
    }

    private func invalidatePendingAndArmed() {
        armedChangeCount = nil
        if pending != nil {
            pending?.registrationAllowed = false
            pending?.deferredPaste = false
        }
    }

    private func schedulePoll(generation: UInt64, attempt: Int) {
        queue.asyncAfter(deadline: .now() + pollingInterval) { [weak self] in
            self?.poll(generation: generation, attempt: attempt)
        }
    }

    private func poll(generation requestGeneration: UInt64, attempt: Int) {
        let snapshot = environment.pasteboardSnapshot()
        let currentContext = environment.focusedFileListContext()
        lock.lock()
        guard let pending, pending.generation == requestGeneration else {
            lock.unlock()
            return
        }
        if currentContext != pending.context {
            self.pending?.registrationAllowed = false
            self.pending?.deferredPaste = false
        }
        if snapshot.changeCount != pending.baselineChangeCount {
            let stable = environment.pasteboardSnapshot()
            if stable == snapshot, snapshot.containsFiles,
               self.pending?.registrationAllowed == true,
               currentContext == pending.context {
                armedChangeCount = snapshot.changeCount
                if pending.deferredPaste,
                   environment.focusedFileListContext() == pending.context,
                   environment.pasteboardSnapshot() == snapshot,
                   environment.sendDeferredMove() {
                    armedChangeCount = nil
                }
            }
            self.pending = nil
            lock.unlock()
            return
        }
        if attempt + 1 >= pollingAttempts {
            self.pending = nil
            lock.unlock()
            return
        }
        self.pending = pending
        lock.unlock()
        schedulePoll(generation: requestGeneration, attempt: attempt + 1)
    }

    private static let xKeyCode: Int64 = 7
    private static let cKeyCode: Int64 = 8
    private static let vKeyCode: Int64 = 9
}
