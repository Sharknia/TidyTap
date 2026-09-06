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

public struct ScrollDeltaFields: Equatable, Sendable {
    public var verticalLine: Int64
    public var verticalPoint: Int64
    public var verticalFixed: Int64
    public var horizontalLine: Int64
    public var horizontalPoint: Int64
    public var horizontalFixed: Int64

    public init(
        verticalLine: Int64,
        verticalPoint: Int64,
        verticalFixed: Int64,
        horizontalLine: Int64,
        horizontalPoint: Int64,
        horizontalFixed: Int64
    ) {
        self.verticalLine = verticalLine
        self.verticalPoint = verticalPoint
        self.verticalFixed = verticalFixed
        self.horizontalLine = horizontalLine
        self.horizontalPoint = horizontalPoint
        self.horizontalFixed = horizontalFixed
    }

    func invertingVertical() -> Self? {
        let line = Int64.zero.subtractingReportingOverflow(verticalLine)
        let point = Int64.zero.subtractingReportingOverflow(verticalPoint)
        let fixed = Int64.zero.subtractingReportingOverflow(verticalFixed)
        guard !line.overflow, !point.overflow, !fixed.overflow else { return nil }
        var result = self
        result.verticalLine = line.partialValue
        result.verticalPoint = point.partialValue
        result.verticalFixed = fixed.partialValue
        return result
    }
}

public struct ScrollObservation: Equatable, Sendable {
    public let timestampNanoseconds: UInt64
    public let isContinuous: Bool
    public let deltas: ScrollDeltaFields
    public let phase: ScrollPhaseBits
    public let momentumPhase: ScrollPhaseBits

    public init(
        timestampNanoseconds: UInt64,
        isContinuous: Bool,
        deltas: ScrollDeltaFields,
        phase: ScrollPhaseBits,
        momentumPhase: ScrollPhaseBits
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.isContinuous = isContinuous
        self.deltas = deltas
        self.phase = phase
        self.momentumPhase = momentumPhase
    }
}

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
            let hasLineDelta = observation.deltas.verticalLine != 0 || observation.deltas.horizontalLine != 0
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

public enum ScrollMutation: Equatable, Sendable {
    case passThrough
    case reverseVerticalDeltas(ScrollDeltaFields)
    case setVerticalScrollStep(lines: Int64)
}

public struct ScrollProcessingResult: Equatable, Sendable {
    public let classification: InputDeviceClass
    public let mutation: ScrollMutation

    public init(
        classification: InputDeviceClass,
        mutation: ScrollMutation
    ) {
        self.classification = classification
        self.mutation = mutation
    }
}

public struct ScrollController: Sendable {
    private var classifier: ScrollClassifier

    public init(classifier: ScrollClassifier = ScrollClassifier()) {
        self.classifier = classifier
    }

    public mutating func observeGesture(at timestampNanoseconds: UInt64) {
        classifier.observeGesture(at: timestampNanoseconds)
    }

    public mutating func process(
        _ observation: ScrollObservation,
        reverseMouseScroll: Bool = true,
        fixedMouseWheelStepEnabled: Bool = false,
        mouseWheelStepLines: Int = 3
    ) -> ScrollProcessingResult {
        let classification = classifier.classify(observation)
        guard
            classification == .discreteMouse,
            observation.deltas.verticalLine != 0
        else {
            return ScrollProcessingResult(
                classification: classification,
                mutation: .passThrough
            )
        }

        let isSingleLineStep = observation.deltas.verticalLine == 1
            || observation.deltas.verticalLine == -1
        if fixedMouseWheelStepEnabled, isSingleLineStep {
            let clampedStep = Int64(min(max(mouseWheelStepLines, 1), 10))
            let originalDirection: Int64 = observation.deltas.verticalLine > 0 ? 1 : -1
            let outputDirection: Int64 = reverseMouseScroll ? -originalDirection : originalDirection
            return ScrollProcessingResult(
                classification: classification,
                mutation: .setVerticalScrollStep(lines: outputDirection * clampedStep)
            )
        }

        guard
            reverseMouseScroll,
            let inverted = observation.deltas.invertingVertical()
        else {
            return ScrollProcessingResult(
                classification: classification,
                mutation: .passThrough
            )
        }
        return ScrollProcessingResult(
            classification: classification,
            mutation: .reverseVerticalDeltas(inverted)
        )
    }
}
