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

public struct ButtonPressGate: Sendable {
    private var pressedButtons: Set<Int64> = []

    public init() {}

    /// Returns true exactly once for a button until its matching up event.
    public mutating func registerDown(button: Int64) -> Bool {
        pressedButtons.insert(button).inserted
    }

    /// Returns whether the button had a matching accepted down event.
    public mutating func registerUp(button: Int64) -> Bool {
        pressedButtons.remove(button) != nil
    }
}
