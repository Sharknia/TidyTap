@preconcurrency import AppKit
import ApplicationServices
import Foundation

public struct CGInputPermissionChecker: InputPermissionChecking {
    public init() {}

    public var accessibilityAllowed: Bool { CGPreflightPostEventAccess() }
    public var inputMonitoringAllowed: Bool { CGPreflightListenEventAccess() }
}

public final class CGEventTapBackend: EventTapBackend, @unchecked Sendable {
    public static func markSynthetic(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: FinderSystemEnvironment.syntheticEventMarker)
    }

    private let lock = NSLock()
    private var handler: EventTapHandler?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?
    private var finderCutPaste: FinderCutPasteController?
    private var clipboardShortcut: ClipboardShortcut?
    private var clipboardKeyDown = false
    private let feedbackHandler: @Sendable (FinderFeedback) -> Void
    private let clipboardShortcutHandler: @Sendable () -> Void

    public init(
        feedbackHandler: @escaping @Sendable (FinderFeedback) -> Void = { _ in },
        clipboardShortcutHandler: @escaping @Sendable () -> Void = {}
    ) {
        self.feedbackHandler = feedbackHandler
        self.clipboardShortcutHandler = clipboardShortcutHandler
    }

    public func install(
        configuration: EventTapConfiguration,
        captureSideButtons: Bool,
        handler: @escaping EventTapHandler
    ) throws {
        uninstall()
        lock.lock()
        self.handler = handler
        lock.unlock()

        var eventMask: CGEventMask = 0
        if configuration.needsScrollProcessing {
            eventMask |= Self.mask(for: .scrollWheel)
        }
        if captureSideButtons {
            eventMask |= Self.mask(for: .otherMouseDown)
            eventMask |= Self.mask(for: .otherMouseUp)
        }
        if configuration.finderCutPasteEnabled || configuration.clipboardShortcut != nil {
            eventMask |= Self.mask(for: .keyDown)
            eventMask |= Self.mask(for: .keyUp)
        }
        setClipboardShortcut(configuration.clipboardShortcut)
        if configuration.finderCutPasteEnabled {
            finderCutPaste = FinderCutPasteController(
                environment: FinderSystemEnvironment(),
                feedbackHandler: feedbackHandler
            )
            finderCutPaste?.setEnabled(true)
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let backend = Unmanaged<CGEventTapBackend>.fromOpaque(userInfo).takeUnretainedValue()
            return backend.process(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            clearHandler()
            throw InputEngineError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        if configuration.needsScrollProcessing {
            installGestureMonitor()
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            uninstall()
            throw InputEngineError.eventTapCreationFailed
        }
    }

    public func enable() throws {
        guard let tap else { throw InputEngineError.eventTapRecoveryFailed }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            throw InputEngineError.eventTapRecoveryFailed
        }
    }

    public func uninstall() {
        if let gestureMonitor {
            NSEvent.removeMonitor(gestureMonitor)
        }
        gestureMonitor = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        finderCutPaste?.setEnabled(false)
        finderCutPaste = nil
        setClipboardShortcut(nil)
        clearHandler()
    }

    deinit {
        uninstall()
    }

    private func installGestureMonitor() {
        let mask: NSEvent.EventTypeMask = [
            .gesture,
            .magnify,
            .swipe,
            .rotate,
            .beginGesture,
            .endGesture,
            .smartMagnify
        ]
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            _ = currentHandler()?(.gesture(timestampNanoseconds: UInt64(event.timestamp * 1_000_000_000)))
        }
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown || type == .keyUp {
            return processKeyboard(type: type, event: event)
        }
        let input: EventTapInput
        switch type {
        case .tapDisabledByTimeout:
            finderCutPaste?.resetAfterTapDisable()
            clipboardKeyDown = false
            input = .disabled(.timeout)
        case .tapDisabledByUserInput:
            finderCutPaste?.resetAfterTapDisable()
            clipboardKeyDown = false
            input = .disabled(.userInput)
        case .scrollWheel:
            input = .scroll(Self.scrollObservation(from: event))
        case .otherMouseDown:
            input = .buttonDown(event.getIntegerValueField(.mouseEventButtonNumber))
        case .otherMouseUp:
            input = .buttonUp(event.getIntegerValueField(.mouseEventButtonNumber))
        default:
            return Unmanaged.passUnretained(event)
        }

        switch Self.apply(currentHandler()?(input) ?? .passThrough, to: event) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        }
    }

    private func processKeyboard(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !FinderSystemEnvironment.isSynthetic(event) else {
            return Unmanaged.passUnretained(event)
        }
        if handleClipboardShortcut(type: type, event: event) {
            return nil
        }
        guard let finderCutPaste else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isDown = type == .keyDown
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isDown && !Self.isUnmodifiedCommand(event.flags) {
            return Unmanaged.passUnretained(event)
        }
        let disposition = finderCutPaste.handle(
            keyCode: keyCode,
            isDown: isDown,
            isRepeat: isRepeat
        )
        switch disposition {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        case .replaceWithCopy:
            event.setIntegerValueField(.keyboardEventKeycode, value: 8)
            return Unmanaged.passUnretained(event)
        case .replaceWithMove:
            event.flags.insert(.maskAlternate)
            return Unmanaged.passUnretained(event)
        }
    }

    /// Keep the matching key-up out of the target app, even if modifiers were
    /// released before the key. Repeats are consumed without reopening the UI.
    func setClipboardShortcut(_ shortcut: ClipboardShortcut?) {
        clipboardShortcut = shortcut
        clipboardKeyDown = false
    }

    func handleClipboardShortcut(type: CGEventType, event: CGEvent) -> Bool {
        guard let clipboardShortcut else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == clipboardShortcut.keyCode else { return false }
        if type == .keyUp, clipboardKeyDown {
            clipboardKeyDown = false
            return true
        }
        guard type == .keyDown else { return false }
        let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
        guard modifiers.rawValue == clipboardShortcut.modifiers else { return false }
        if !clipboardKeyDown {
            clipboardKeyDown = true
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                clipboardShortcutHandler()
            }
        }
        return true
    }

    private static func isUnmodifiedCommand(_ flags: CGEventFlags) -> Bool {
        let modifiers = flags.intersection([
            .maskCommand, .maskAlternate, .maskControl, .maskShift
        ])
        return modifiers == .maskCommand
    }

    enum EventDisposition {
        case passThrough
        case consume
    }

    static func apply(_ output: EventTapOutput, to event: CGEvent) -> EventDisposition {
        switch output {
        case .passThrough:
            return .passThrough
        case .consume:
            return .consume
        case .replaceScrollDeltas(let deltas):
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: deltas.verticalLine)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: deltas.verticalPoint)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: deltas.verticalFixed)
            return .passThrough
        case .setVerticalScrollStep(let lines):
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines)
            return .passThrough
        }
    }

    private func currentHandler() -> EventTapHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    private func clearHandler() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    private static func scrollObservation(from event: CGEvent) -> ScrollObservation {
        ScrollObservation(
            timestampNanoseconds: event.timestamp,
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            deltas: ScrollDeltaFields(
                verticalLine: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                verticalPoint: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                verticalFixed: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
                horizontalLine: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                horizontalPoint: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                horizontalFixed: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)
            ),
            phase: ScrollPhaseBits(
                rawValue: UInt64(bitPattern: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            ),
            momentumPhase: ScrollPhaseBits(
                rawValue: UInt64(bitPattern: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            )
        )
    }

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }
}
