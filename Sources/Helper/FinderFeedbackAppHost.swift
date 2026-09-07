@preconcurrency import AppKit
import Foundation
import TidyTapInputEngine

@MainActor
final class FinderFeedbackAppHost: NSObject {
    static let shared = FinderFeedbackAppHost()

    private var launchedApplication: NSRunningApplication?
    private var launchInFlight = false
    private var launchNonce: UUID?
    private var latestPayload: TidyTapFinderFeedbackPayload?
    private var awaitingApplicationPID: pid_t?

    override private init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(feedbackHostReady(_:)),
            name: TidyTapIPC.finderFeedbackReady,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
    }

    nonisolated static func present(_ feedback: FinderFeedback) {
        DispatchQueue.main.async {
            shared.presentOnMain(feedback)
        }
    }

    private func presentOnMain(_ feedback: FinderFeedback) {
        let payload = TidyTapFinderFeedbackPayload(
            kind: feedback.kind == .moveReady ? .moveReady : .copyReady,
            anchorRect: feedback.anchorRect,
            clipboardChangeCount: feedback.clipboardChangeCount
        )
        latestPayload = payload
        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: TidyTapProduct.appBundleIdentifier
        ).first {
            awaitingApplicationPID = runningApp.processIdentifier
            TidyTapIPC.postFinderFeedback(payload)
            return
        }
        // LaunchServices performs a non-activating app launch. Direct Process
        // execution can activate even an accessory app before its first frame.
        guard !launchInFlight else { return }
        let applicationURL = Bundle.main.bundleURL
        let nonce = UUID()
        var feedbackEnvironment = TidyTapIPC.finderFeedbackEnvironment(payload)
        feedbackEnvironment[TidyTapIPC.finderFeedbackNonceEnvironmentKey] = nonce.uuidString
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.environment = ProcessInfo.processInfo.environment.merging(feedbackEnvironment) {
            _, feedbackValue in feedbackValue
        }
        launchNonce = nonce
        launchInFlight = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { [weak self] app, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.launchNonce == nonce else { return }
                self.launchInFlight = false
                self.launchedApplication = app
                guard let app, let latestPayload = self.latestPayload else { return }
                self.awaitingApplicationPID = app.processIdentifier
                TidyTapIPC.postFinderFeedback(latestPayload)
            }
        }
    }

    @objc private func feedbackHostReady(_ notification: Notification) {
        guard let ready = TidyTapIPC.finderFeedbackReady(in: notification),
              let latestPayload else { return }
        let isOwnedTransientHost = ready.nonce == launchNonce && (launchInFlight || launchedApplication?.isTerminated == false)
        let isAwaitedRegularApp = ready.nonce == nil && ready.processID == awaitingApplicationPID
        guard isOwnedTransientHost || isAwaitedRegularApp else { return }
        awaitingApplicationPID = nil
        TidyTapIPC.postFinderFeedback(latestPayload)
    }
}
