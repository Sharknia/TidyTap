@preconcurrency import AppKit
import ApplicationServices
import Foundation

public enum NavigationDirection: String, Equatable, Sendable {
    case back
    case forward
}

public struct FocusedApplication: Equatable, Sendable {
    public let bundleIdentifier: String
    public let processIdentifier: pid_t
    public let isActive: Bool
    public let hasFocusedWindow: Bool

    public init(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        isActive: Bool,
        hasFocusedWindow: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.hasFocusedWindow = hasFocusedWindow
    }

    public var isSupportedNavigationTarget: Bool {
        isActive
            && hasFocusedWindow
            && (bundleIdentifier == "com.apple.Safari" || bundleIdentifier == "com.apple.finder")
    }
}

public protocol FocusedApplicationProviding: Sendable {
    func focusedApplication() -> FocusedApplication?
}

public protocol NavigationSynthesizing: Sendable {
    func synthesize(_ direction: NavigationDirection, for target: FocusedApplication) -> Bool
}

public protocol ProcessTargetedNavigationPosting: Sendable {
    func post(_ direction: NavigationDirection, to processIdentifier: pid_t) -> Bool
}

public enum ButtonEventDisposition: Equatable, Sendable {
    case passThrough
    case consume
}

private enum ButtonDownOwnership {
    case firstDown
    case repeatedUnowned
    case repeatedOwned
}

private struct ButtonPressOwnership {
    private var pressedButtons: Set<Int64> = []
    private var ownedButtons: Set<Int64> = []

    mutating func registerDown(button: Int64) -> ButtonDownOwnership {
        if ownedButtons.contains(button) { return .repeatedOwned }
        if pressedButtons.contains(button) { return .repeatedUnowned }
        pressedButtons.insert(button)
        return .firstDown
    }

    mutating func claim(button: Int64) -> Bool {
        guard pressedButtons.contains(button) else { return false }
        ownedButtons.insert(button)
        return true
    }

    mutating func registerUp(button: Int64) -> Bool {
        pressedButtons.remove(button)
        return ownedButtons.remove(button) != nil
    }

    mutating func reset() {
        pressedButtons.removeAll()
        ownedButtons.removeAll()
    }

    var hasActivePresses: Bool { !pressedButtons.isEmpty }
}

public final class SideButtonController: @unchecked Sendable {
    private let applicationProvider: any FocusedApplicationProviding
    private let synthesizer: any NavigationSynthesizing
    private let lock = NSLock()
    private var ownership = ButtonPressOwnership()

    public init(
        applicationProvider: any FocusedApplicationProviding,
        synthesizer: any NavigationSynthesizing
    ) {
        self.applicationProvider = applicationProvider
        self.synthesizer = synthesizer
    }

    public var hasActivePresses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownership.hasActivePresses
    }

    public func handleButtonDown(
        _ button: Int64,
        navigationEnabled: Bool = true
    ) -> ButtonEventDisposition {
        guard let direction = Self.direction(for: button) else { return .passThrough }

        lock.lock()
        defer { lock.unlock() }
        let pressState = ownership.registerDown(button: button)
        switch pressState {
        case .repeatedOwned:
            return .consume
        case .repeatedUnowned:
            return .passThrough
        case .firstDown:
            break
        }

        guard navigationEnabled else { return .passThrough }
        guard let target = applicationProvider.focusedApplication(), target.isSupportedNavigationTarget else {
            return .passThrough
        }
        guard synthesizer.synthesize(direction, for: target) else {
            return .passThrough
        }
        let claimed = ownership.claim(button: button)
        return claimed ? .consume : .passThrough
    }

    public func handleButtonUp(_ button: Int64) -> ButtonEventDisposition {
        guard Self.direction(for: button) != nil else { return .passThrough }
        lock.lock()
        let wasOwned = ownership.registerUp(button: button)
        lock.unlock()
        return wasOwned ? .consume : .passThrough
    }

    public func reset() {
        lock.lock()
        ownership.reset()
        lock.unlock()
    }

    public static func direction(for button: Int64) -> NavigationDirection? {
        switch button {
        case 3: .back
        case 4: .forward
        default: nil
        }
    }
}

public struct MacOSFocusedApplicationProvider: FocusedApplicationProviding {
    public init() {}

    public func focusedApplication() -> FocusedApplication? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        return FocusedApplication(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: application.processIdentifier,
            isActive: application.isActive,
            hasFocusedWindow: result == .success && focusedWindow != nil
        )
    }
}

public struct CGNavigationSynthesizer: NavigationSynthesizing {
    private let applicationProvider: any FocusedApplicationProviding
    private let eventPoster: any ProcessTargetedNavigationPosting

    public init(
        applicationProvider: any FocusedApplicationProviding = MacOSFocusedApplicationProvider(),
        eventPoster: any ProcessTargetedNavigationPosting = CGNavigationEventPoster()
    ) {
        self.applicationProvider = applicationProvider
        self.eventPoster = eventPoster
    }

    public func synthesize(_ direction: NavigationDirection, for target: FocusedApplication) -> Bool {
        guard
            target.isSupportedNavigationTarget,
            applicationProvider.focusedApplication() == target
        else {
            return false
        }
        return eventPoster.post(direction, to: target.processIdentifier)
    }
}

public struct CGNavigationEventPoster: ProcessTargetedNavigationPosting {
    public init() {}

    public func post(_ direction: NavigationDirection, to processIdentifier: pid_t) -> Bool {
        guard
            CGPreflightPostEventAccess(),
            let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.virtualKey(for: direction),
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.virtualKey(for: direction),
                keyDown: false
            )
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }

    private static func virtualKey(for direction: NavigationDirection) -> CGKeyCode {
        switch direction {
        case .back: 33
        case .forward: 30
        }
    }
}
