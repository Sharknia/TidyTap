import Foundation

public enum InputDeviceClass: String, Equatable, Sendable {
    case discreteMouse = "discrete-mouse"
    case trackpad
    case unknown
}

public struct ScrollPhaseBits: OptionSet, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let began = Self(rawValue: 1 << 0)
    public static let changed = Self(rawValue: 1 << 1)
    public static let ended = Self(rawValue: 1 << 2)
    public static let cancelled = Self(rawValue: 1 << 3)
    public static let mayBegin = Self(rawValue: 1 << 7)

    public static let directGestureActivity: Self = [.began, .changed, .ended, .cancelled]
    public static let terminal: Self = [.ended, .cancelled]
}

public struct ScrollObservation: Equatable, Sendable {
    public let timestampNanoseconds: UInt64
    public let isContinuous: Bool
    public let verticalLineDelta: Int64
    public let horizontalLineDelta: Int64
    public let phase: ScrollPhaseBits
    public let momentumPhase: ScrollPhaseBits

    public init(
        timestampNanoseconds: UInt64,
        isContinuous: Bool,
        verticalLineDelta: Int64,
        horizontalLineDelta: Int64,
        phase: ScrollPhaseBits,
        momentumPhase: ScrollPhaseBits
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.isContinuous = isContinuous
        self.verticalLineDelta = verticalLineDelta
        self.horizontalLineDelta = horizontalLineDelta
        self.phase = phase
        self.momentumPhase = momentumPhase
    }
}

/// Implements only the MVP's deliberately narrow public-event heuristic.
/// It does not attempt to identify hardware from private IOHID metadata.
public struct ScrollClassifier: Sendable {
    public static let defaultLinkWindowNanoseconds: UInt64 = 750_000_000

    private let linkWindowNanoseconds: UInt64
    private var lastGestureTimestamp: UInt64?
    private var momentumIsLinked = false

    public init(linkWindowNanoseconds: UInt64 = Self.defaultLinkWindowNanoseconds) {
        self.linkWindowNanoseconds = linkWindowNanoseconds
    }

    public mutating func observeGesture(at timestampNanoseconds: UInt64) {
        lastGestureTimestamp = timestampNanoseconds
    }

    public mutating func classify(_ observation: ScrollObservation) -> InputDeviceClass {
        guard observation.isContinuous else {
            let hasLineDelta = observation.verticalLineDelta != 0 || observation.horizontalLineDelta != 0
            return hasLineDelta ? .discreteMouse : .unknown
        }

        if !observation.phase.intersection(.directGestureActivity).isEmpty {
            lastGestureTimestamp = observation.timestampNanoseconds

            if !observation.momentumPhase.isEmpty {
                momentumIsLinked = true
            }
            if !observation.momentumPhase.intersection(.terminal).isEmpty {
                momentumIsLinked = false
            }
            return .trackpad
        }

        if !observation.momentumPhase.isEmpty {
            if observation.momentumPhase.contains(.began) {
                momentumIsLinked = isRecentGesture(at: observation.timestampNanoseconds)
            }

            let result: InputDeviceClass = momentumIsLinked ? .trackpad : .unknown
            if !observation.momentumPhase.intersection(.terminal).isEmpty {
                momentumIsLinked = false
            }
            return result
        }

        return isRecentGesture(at: observation.timestampNanoseconds) ? .trackpad : .unknown
    }

    private func isRecentGesture(at timestampNanoseconds: UInt64) -> Bool {
        guard let lastGestureTimestamp, timestampNanoseconds >= lastGestureTimestamp else {
            return false
        }
        return timestampNanoseconds - lastGestureTimestamp <= linkWindowNanoseconds
    }
}

public enum ButtonDownOwnership: Equatable, Sendable {
    case firstDown
    case repeatedUnowned
    case repeatedOwned
}

public enum ButtonDownDisposition: Equatable, Sendable {
    case passThrough
    case attemptNavigation
    case consume
}

public enum ButtonUpDisposition: Equatable, Sendable {
    case passThrough
    case consume
}

/// Tracks whether a callback has claimed an entire physical button press.
/// Claiming happens only after the first down successfully triggers navigation.
public struct ButtonPressOwnership: Sendable {
    private var pressedButtons: Set<Int64> = []
    private var ownedButtons: Set<Int64> = []

    public init() {}

    public mutating func registerDown(button: Int64) -> ButtonDownOwnership {
        if ownedButtons.contains(button) {
            return .repeatedOwned
        }
        if pressedButtons.contains(button) {
            return .repeatedUnowned
        }
        pressedButtons.insert(button)
        return .firstDown
    }

    /// Claims future repeats and the matching up. Call only after synthesis succeeds.
    @discardableResult
    public mutating func claimPress(button: Int64) -> Bool {
        guard pressedButtons.contains(button) else { return false }
        ownedButtons.insert(button)
        return true
    }

    /// Returns true when the callback owns and must consume this up event.
    public mutating func registerUp(button: Int64) -> Bool {
        pressedButtons.remove(button)
        return ownedButtons.remove(button) != nil
    }
}

/// Pure callback policy used by the Core Graphics event tap.
public struct ButtonCallbackState: Sendable {
    private var ownership = ButtonPressOwnership()

    public init() {}

    public mutating func buttonDown(
        button: Int64,
        isEligibleNavigationTarget: Bool
    ) -> ButtonDownDisposition {
        switch ownership.registerDown(button: button) {
        case .firstDown:
            return isEligibleNavigationTarget ? .attemptNavigation : .passThrough
        case .repeatedUnowned:
            return .passThrough
        case .repeatedOwned:
            return .consume
        }
    }

    /// Commits ownership only after the callback successfully posts navigation.
    @discardableResult
    public mutating func navigationDidSucceed(button: Int64) -> Bool {
        ownership.claimPress(button: button)
    }

    public mutating func buttonUp(button: Int64) -> ButtonUpDisposition {
        ownership.registerUp(button: button) ? .consume : .passThrough
    }
}
