import Foundation

/// Keeps a paste request alive only while the original target can still be verified.
@MainActor
final class ClipboardPasteFocusRecovery {
    enum FocusObservation: Equatable {
        case original
        case different
        case noValue
        case otherError(Int32)
    }

    enum Outcome: Equatable {
        case pasted(error: String?, retries: Int)
        case failed(reason: String, retries: Int, axError: Int32?, originalMatched: Bool)
        case superseded
    }

    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let retryInterval: TimeInterval = 0.03
    static let maximumRetries = 5

    private struct Request {
        let id: UUID
        let originalCaptured: Bool
        let targetIsReady: () -> Bool
        let inspectFocus: () -> FocusObservation
        let paste: () -> String?
        let completion: (Outcome) -> Void
        var retries = 0
    }

    private let schedule: Scheduler
    private var active: Request?

    init(schedule: @escaping Scheduler = { delay, action in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }) {
        self.schedule = schedule
    }

    func start(
        id: UUID,
        originalCaptured: Bool,
        targetIsReady: @escaping () -> Bool,
        inspectFocus: @escaping () -> FocusObservation,
        paste: @escaping () -> String?,
        completion: @escaping (Outcome) -> Void
    ) {
        cancelActive()
        active = Request(
            id: id,
            originalCaptured: originalCaptured,
            targetIsReady: targetIsReady,
            inspectFocus: inspectFocus,
            paste: paste,
            completion: completion
        )
        checkFocus(for: id)
    }

    func cancelActive() {
        guard let request = active else { return }
        active = nil
        request.completion(.superseded)
    }

    private func checkFocus(for id: UUID) {
        guard var request = active, request.id == id else { return }
        guard request.targetIsReady() else {
            finish(request, with: .failed(
                reason: "targetUnavailable", retries: request.retries,
                axError: nil, originalMatched: false
            ))
            return
        }
        guard request.originalCaptured else {
            finish(request, with: .failed(
                reason: "focusChanged", retries: request.retries,
                axError: nil, originalMatched: false
            ))
            return
        }

        switch request.inspectFocus() {
        case .original:
            guard request.targetIsReady() else {
                finish(request, with: .failed(
                    reason: "targetUnavailable", retries: request.retries,
                    axError: nil, originalMatched: true
                ))
                return
            }
            active = nil
            let error = request.paste()
            request.completion(.pasted(error: error, retries: request.retries))
        case .different:
            finish(request, with: .failed(
                reason: "focusChanged", retries: request.retries,
                axError: nil, originalMatched: false
            ))
        case .otherError(let error):
            finish(request, with: .failed(
                reason: "focusChanged", retries: request.retries,
                axError: error, originalMatched: false
            ))
        case .noValue:
            guard request.retries < Self.maximumRetries else {
                finish(request, with: .failed(
                    reason: "focusChanged", retries: request.retries,
                    axError: -25212, originalMatched: false
                ))
                return
            }
            request.retries += 1
            active = request
            schedule(Self.retryInterval) { [weak self] in
                self?.checkFocus(for: id)
            }
        }
    }

    private func finish(_ request: Request, with outcome: Outcome) {
        active = nil
        request.completion(outcome)
    }
}
