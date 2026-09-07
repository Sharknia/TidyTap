import CoreGraphics
import Foundation

public struct FinderFeedback: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case moveReady
        case copyReady
    }

    public let kind: Kind
    public let anchorRect: CGRect
    public let clipboardChangeCount: Int

    public init(kind: Kind, anchorRect: CGRect, clipboardChangeCount: Int) {
        self.kind = kind
        self.anchorRect = anchorRect
        self.clipboardChangeCount = clipboardChangeCount
    }
}

struct FinderContext: Equatable, Sendable {
    let processIdentifier: Int32
    let windowIdentifier: UInt
}

struct FinderPasteboardSnapshot: Equatable, Sendable {
    let changeCount: Int
    let containsFiles: Bool
}

struct FinderFeedbackTarget: Equatable, Sendable {
    let context: FinderContext
    let selectionIdentifier: UInt
    let anchorRect: CGRect
}

struct FinderSelectionSnapshot: Equatable, Sendable {
    let context: FinderContext
    let feedbackTarget: FinderFeedbackTarget?
}

protocol FinderCutPasteEnvironment: Sendable {
    func focusedFileListContext() -> FinderContext?
    func pasteboardSnapshot() -> FinderPasteboardSnapshot
    func selectionSnapshot() -> FinderSelectionSnapshot?
    func prepareDeferredMove() -> (@Sendable () -> Void)?
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
        let feedbackTarget: FinderFeedbackTarget?
        let feedbackGeneration: UInt64
        var registrationAllowed: Bool
        var deferredPaste: Bool
    }

    private struct PendingFeedback {
        let generation: UInt64
        let baselineChangeCount: Int
        let target: FinderFeedbackTarget
        let kind: FinderFeedback.Kind
    }

    private let environment: any FinderCutPasteEnvironment
    private let queue: DispatchQueue
    private let pollingInterval: TimeInterval
    private let pollingAttempts: Int
    // Called while the state lock is held so invalidation and delivery have a total order.
    // Production handlers must only enqueue the feedback and return immediately.
    private let feedbackHandler: @Sendable (FinderFeedback) -> Void
    private let lock = NSLock()
    private var enabled = false
    private var generation: UInt64 = 0
    private var feedbackGeneration: UInt64 = 0
    private var pending: PendingCopy?
    private var pendingFeedback: PendingFeedback?
    private var armedChangeCount: Int?
    private var transformedCopyKeyIsDown = false
    private var transformedMoveKeyIsDown = false
    private var consumedCopyKeyIsDown = false
    private var consumedPasteKeyIsDown = false
    private var copyFeedbackKeyIsDown = false

    init(
        environment: any FinderCutPasteEnvironment,
        queue: DispatchQueue? = nil,
        pollingInterval: TimeInterval = 0.02,
        pollingAttempts: Int = 25,
        feedbackHandler: @escaping @Sendable (FinderFeedback) -> Void = { _ in }
    ) {
        self.environment = environment
        self.queue = queue ?? DispatchQueue(
            label: "com.tidytap.finder-cut-paste",
            qos: .userInitiated
        )
        self.pollingInterval = pollingInterval
        self.pollingAttempts = pollingAttempts
        self.feedbackHandler = feedbackHandler
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
        feedbackGeneration &+= 1
        pending = nil
        pendingFeedback = nil
        armedChangeCount = nil
        transformedCopyKeyIsDown = false
        transformedMoveKeyIsDown = false
        consumedCopyKeyIsDown = false
        consumedPasteKeyIsDown = false
        copyFeedbackKeyIsDown = false
    }

    func handle(keyCode: Int64, isDown: Bool, isRepeat: Bool) -> FinderKeyDisposition {
        let selectionSnapshot: FinderSelectionSnapshot?
        if isDown, !isRepeat, keyCode == Self.xKeyCode || keyCode == Self.cKeyCode {
            lock.lock()
            let shouldCapture = enabled
            lock.unlock()
            selectionSnapshot = shouldCapture ? environment.selectionSnapshot() : nil
        } else {
            selectionSnapshot = nil
        }

        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return .passThrough }

        if keyCode == Self.xKeyCode {
            return handleX(isDown: isDown, isRepeat: isRepeat, selectionSnapshot: selectionSnapshot)
        }
        if keyCode == Self.cKeyCode {
            handleC(isDown: isDown, isRepeat: isRepeat, selectionSnapshot: selectionSnapshot)
            return .passThrough
        }
        if keyCode == Self.vKeyCode {
            return handleV(isDown: isDown, isRepeat: isRepeat)
        }
        return .passThrough
    }

    private func handleC(
        isDown: Bool,
        isRepeat: Bool,
        selectionSnapshot: FinderSelectionSnapshot?
    ) {
        guard isDown else {
            copyFeedbackKeyIsDown = false
            return
        }
        guard !isRepeat, !copyFeedbackKeyIsDown else { return }
        copyFeedbackKeyIsDown = true
        invalidatePendingAndArmed()
        feedbackGeneration &+= 1
        let requestGeneration = feedbackGeneration
        let baseline = environment.pasteboardSnapshot().changeCount
        guard let target = selectionSnapshot?.feedbackTarget else { return }
        pendingFeedback = PendingFeedback(
            generation: requestGeneration,
            baselineChangeCount: baseline,
            target: target,
            kind: .copyReady
        )
        scheduleFeedbackPoll(generation: requestGeneration, attempt: 0)
    }

    private func handleX(
        isDown: Bool,
        isRepeat: Bool,
        selectionSnapshot: FinderSelectionSnapshot?
    ) -> FinderKeyDisposition {
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
        guard let selectionSnapshot else {
            invalidatePendingAndArmed()
            return .passThrough
        }
        guard pending == nil else {
            consumedCopyKeyIsDown = true
            return .consume
        }

        generation &+= 1
        feedbackGeneration &+= 1
        let requestGeneration = generation
        let baseline = environment.pasteboardSnapshot().changeCount
        armedChangeCount = nil
        pending = PendingCopy(
            generation: requestGeneration,
            baselineChangeCount: baseline,
            context: selectionSnapshot.context,
            feedbackTarget: selectionSnapshot.feedbackTarget,
            feedbackGeneration: feedbackGeneration,
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
        pending?.registrationAllowed = false
        pending?.deferredPaste = false
        feedbackGeneration &+= 1
        pendingFeedback = nil
    }

    private func schedulePoll(generation: UInt64, attempt: Int) {
        queue.asyncAfter(deadline: .now() + pollingInterval) { [weak self] in
            self?.poll(generation: generation, attempt: attempt)
        }
    }

    private func scheduleFeedbackPoll(generation: UInt64, attempt: Int) {
        queue.asyncAfter(deadline: .now() + pollingInterval) { [weak self] in
            self?.pollFeedback(generation: generation, attempt: attempt)
        }
    }

    private func poll(generation requestGeneration: UInt64, attempt: Int) {
        let snapshot = environment.pasteboardSnapshot()
        let selectionSnapshot = environment.selectionSnapshot()
        let confirmationSnapshot = environment.pasteboardSnapshot()
        let currentContext = selectionSnapshot?.context
        var shouldSendDeferredMove = false
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
            if confirmationSnapshot == snapshot, snapshot.containsFiles,
               self.pending?.registrationAllowed == true,
               currentContext == pending.context {
                armedChangeCount = snapshot.changeCount
                if let initialTarget = pending.feedbackTarget,
                   selectionSnapshot?.feedbackTarget == initialTarget,
                   feedbackGeneration == pending.feedbackGeneration {
                    feedbackHandler(FinderFeedback(
                        kind: .moveReady,
                        anchorRect: initialTarget.anchorRect,
                        clipboardChangeCount: snapshot.changeCount
                    ))
                }
                shouldSendDeferredMove = pending.deferredPaste
            }
            self.pending = nil
            lock.unlock()
            if shouldSendDeferredMove,
               environment.focusedFileListContext() == pending.context,
               environment.pasteboardSnapshot() == snapshot,
               let deferredMove = environment.prepareDeferredMove() {
                lock.lock()
                let requestIsCurrent = generation == requestGeneration
                    && armedChangeCount == snapshot.changeCount
                if requestIsCurrent {
                    deferredMove()
                    armedChangeCount = nil
                }
                lock.unlock()
            }
            return
        }
        if attempt + 1 >= pollingAttempts {
            self.pending = nil
            lock.unlock()
            return
        }
        lock.unlock()
        schedulePoll(generation: requestGeneration, attempt: attempt + 1)
    }

    private func pollFeedback(generation requestGeneration: UInt64, attempt: Int) {
        let snapshot = environment.pasteboardSnapshot()
        let currentTarget = environment.selectionSnapshot()?.feedbackTarget
        let confirmationSnapshot = environment.pasteboardSnapshot()
        lock.lock()
        guard feedbackGeneration == requestGeneration,
              let pendingFeedback, pendingFeedback.generation == requestGeneration else {
            lock.unlock()
            return
        }
        if snapshot.changeCount != pendingFeedback.baselineChangeCount {
            self.pendingFeedback = nil
            if confirmationSnapshot == snapshot,
               snapshot.containsFiles,
               currentTarget == pendingFeedback.target {
                feedbackHandler(.init(
                    kind: pendingFeedback.kind,
                    anchorRect: pendingFeedback.target.anchorRect,
                    clipboardChangeCount: snapshot.changeCount
                ))
            }
            lock.unlock()
            return
        }
        if attempt + 1 >= pollingAttempts {
            self.pendingFeedback = nil
            lock.unlock()
            return
        }
        lock.unlock()
        scheduleFeedbackPoll(generation: requestGeneration, attempt: attempt + 1)
    }

    private static let xKeyCode: Int64 = 7
    private static let cKeyCode: Int64 = 8
    private static let vKeyCode: Int64 = 9
}
