import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import InputEventProbeCore

private struct Options {
    var synthesizeNavigation = false
    var duration: TimeInterval?

    static func parse(_ arguments: [String]) throws -> Self {
        var result = Self()
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--synthesize-navigation":
                result.synthesizeNavigation = true
            case "--duration":
                index += 1
                guard index < arguments.count,
                      let seconds = TimeInterval(arguments[index]),
                      seconds > 0 else {
                    throw ProbeError.usage("--duration requires a positive number of seconds")
                }
                result.duration = seconds
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.usage("unknown argument: \(arguments[index])")
            }
            index += 1
        }
        return result
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case permission(String)
    case eventTapCreation

    var description: String {
        switch self {
        case .usage(let message), .permission(let message): return message
        case .eventTapCreation: return "could not create the event tap; verify Input Monitoring/Accessibility permission"
        }
    }
}

private final class LockedState {
    private let lock = NSLock()
    private var classifier = ScrollClassifier()
    private var buttonGate = ButtonPressGate()
    private var handledButtons: Set<Int64> = []
    private var scrollCounts: [InputDeviceClass: Int] = [:]
    private var buttonCounts: [Int64: Int] = [:]

    func observeGesture(timestamp: UInt64) {
        lock.lock()
        classifier.observeGesture(at: timestamp)
        lock.unlock()
    }

    func classify(_ observation: ScrollObservation) -> InputDeviceClass {
        lock.lock()
        defer { lock.unlock() }
        let result = classifier.classify(observation)
        scrollCounts[result, default: 0] += 1
        return result
    }

    func acceptButtonDown(_ button: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buttonCounts[button, default: 0] += 1
        return buttonGate.registerDown(button: button)
    }

    func markHandled(_ button: Int64) {
        lock.lock()
        handledButtons.insert(button)
        lock.unlock()
    }

    func releaseButton(_ button: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _ = buttonGate.registerUp(button: button)
        return handledButtons.remove(button) != nil
    }

    func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        let scroll = InputDeviceClass.allCasesForReport
            .map { "\($0.rawValue)=\(scrollCounts[$0, default: 0])" }
            .joined(separator: " ")
        let buttons = buttonCounts.keys.sorted()
            .map { "button\($0)=\(buttonCounts[$0, default: 0])" }
            .joined(separator: " ")
        return "summary scroll{\(scroll)} buttons{\(buttons.isEmpty ? "none" : buttons)}"
    }
}

private extension InputDeviceClass {
    static let allCasesForReport: [Self] = [.discreteMouse, .trackpad, .unknown]
}

private enum NavigationDirection: String {
    case back
    case forward

    var virtualKeyCode: CGKeyCode {
        switch self {
        case .back: return 33 // ANSI left bracket
        case .forward: return 30 // ANSI right bracket
        }
    }
}

private final class EventProbe {
    private let options: Options
    private let state = LockedState()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?
    private var stopTimer: Timer?

    init(options: Options) {
        self.options = options
    }

    func run() throws {
        guard CGPreflightListenEventAccess() else {
            throw ProbeError.permission(
                "Input Monitoring permission is missing. Add the terminal or built executable in System Settings > Privacy & Security > Input Monitoring, then relaunch."
            )
        }
        if options.synthesizeNavigation && !CGPreflightPostEventAccess() {
            throw ProbeError.permission(
                "Accessibility permission is missing. Navigation mode needs both Input Monitoring and Accessibility permission."
            )
        }

        let eventMask = mask(for: .scrollWheel) | mask(for: .otherMouseDown) | mask(for: .otherMouseUp)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let probe = Unmanaged<EventProbe>.fromOpaque(userInfo).takeUnretainedValue()
            return probe.handle(type: type, event: event)
        }

        let tapOptions: CGEventTapOptions = options.synthesizeNavigation ? .defaultTap : .listenOnly
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { throw ProbeError.eventTapCreation }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installGestureMonitor()

        print("mode=\(options.synthesizeNavigation ? "navigation-enabled" : "observe-only") listenAccess=true postAccess=\(CGPreflightPostEventAccess())")
        print("privacy=no keyboard events, text, pointer coordinates, or event payloads are recorded")
        if options.synthesizeNavigation {
            print("navigation=button3:back button4:forward targets=com.apple.Safari,com.apple.finder")
        }

        if let duration = options.duration {
            stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
        }

        CFRunLoopRun()
    }

    private func installGestureMonitor() {
        let gestureMask: NSEvent.EventTypeMask = [
            .gesture, .magnify, .swipe, .rotate, .beginGesture, .endGesture, .smartMagnify
        ]
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: gestureMask) { [weak self] event in
            guard let self else { return }
            let timestamp = UInt64(event.timestamp * 1_000_000_000)
            self.state.observeGesture(timestamp: timestamp)
            print("gesture type=\(Self.gestureName(event.type))")
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            print("tap reenabled reason=\(type == .tapDisabledByTimeout ? "timeout" : "user-input")")
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .scrollWheel:
            observeScroll(event)
        case .otherMouseDown:
            return handleButtonDown(event)
        case .otherMouseUp:
            return handleButtonUp(event)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func observeScroll(_ event: CGEvent) {
        let observation = ScrollObservation(
            timestampNanoseconds: event.timestamp,
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            verticalLineDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            horizontalLineDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            phase: ScrollPhaseBits(rawValue: UInt64(bitPattern: event.getIntegerValueField(.scrollWheelEventScrollPhase))),
            momentumPhase: ScrollPhaseBits(rawValue: UInt64(bitPattern: event.getIntegerValueField(.scrollWheelEventMomentumPhase)))
        )
        let classification = state.classify(observation)
        print(
            "scroll class=\(classification.rawValue) continuous=\(observation.isContinuous) " +
            "verticalLines=\(observation.verticalLineDelta) horizontalLines=\(observation.horizontalLineDelta) " +
            "phase=\(observation.phase.rawValue) momentum=\(observation.momentumPhase.rawValue)"
        )
    }

    private func handleButtonDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let firstDown = state.acceptButtonDown(button)
        print("button direction=down number=\(button) firstDown=\(firstDown)")

        guard options.synthesizeNavigation,
              firstDown,
              let direction = Self.direction(for: button),
              let target = Self.focusedNavigationTarget(),
              postNavigation(direction) else {
            return Unmanaged.passUnretained(event)
        }

        state.markHandled(button)
        print("navigation sent=\(direction.rawValue) target=\(target)")
        return nil
    }

    private func handleButtonUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let wasHandled = state.releaseButton(button)
        print("button direction=up number=\(button) consumed=\(wasHandled)")
        return wasHandled ? nil : Unmanaged.passUnretained(event)
    }

    private func postNavigation(_ direction: NavigationDirection) -> Bool {
        guard CGPreflightPostEventAccess(),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: direction.virtualKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: direction.virtualKeyCode, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func focusedNavigationTarget() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier == "com.apple.Safari" || bundleIdentifier == "com.apple.finder",
              application.isActive else {
            return nil
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success, focusedWindow != nil else { return nil }
        return bundleIdentifier
    }

    private static func direction(for button: Int64) -> NavigationDirection? {
        switch button {
        case 3: return .back
        case 4: return .forward
        default: return nil
        }
    }

    private static func gestureName(_ type: NSEvent.EventType) -> String {
        switch type {
        case .gesture: return "gesture"
        case .magnify: return "magnify"
        case .swipe: return "swipe"
        case .rotate: return "rotate"
        case .beginGesture: return "begin"
        case .endGesture: return "end"
        case .smartMagnify: return "smart-magnify"
        default: return "other"
        }
    }

    private func stop() {
        print(state.summary())
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        gestureMonitor = nil
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        self.runLoopSource = nil
        tap = nil
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

private func mask(for type: CGEventType) -> CGEventMask {
    CGEventMask(1) << type.rawValue
}

private func printUsage() {
    print(
        """
        Usage: InputEventProbe [--duration SECONDS] [--synthesize-navigation]

          default                  Observe and report scroll/gesture/button metadata only.
          --duration SECONDS       Stop automatically and print aggregate counts.
          --synthesize-navigation  Consume button 3/4 and post Command-[ / Command-]
                                   only to a focused Safari/Finder window.
        """
    )
}

do {
    let options = try Options.parse(CommandLine.arguments)
    try EventProbe(options: options).run()
} catch {
    fputs("InputEventProbe: \(error)\n", stderr)
    fputs("Run InputEventProbe --help for usage.\n", stderr)
    exit(EXIT_FAILURE)
}
