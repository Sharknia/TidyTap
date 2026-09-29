@preconcurrency import AppKit
import ApplicationServices
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
        let applicationURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: TidyTapProduct.appBundleIdentifier
        ).first(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == applicationURL }) {
            awaitingApplicationPID = runningApp.processIdentifier
            TidyTapIPC.postFinderFeedback(payload)
            return
        }
        // LaunchServices performs a non-activating app launch. Direct Process
        // execution can activate even an accessory app before its first frame.
        guard !launchInFlight else { return }
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

@MainActor
final class ClipboardHistoryAppHost: NSObject {
    static let shared = ClipboardHistoryAppHost()

    private struct PasteSession {
        let id: UUID
        let targetPID: pid_t
        let focusedElement: AXUIElement?
        let focusCaptureError: Int32
    }

    private var pasteSession: PasteSession?
    private let focusRecovery = ClipboardPasteFocusRecovery()

    override private init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(pasteRequested(_:)),
            name: TidyTapIPC.clipboardHistoryPaste,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
    }

    nonisolated static func present() {
        DispatchQueue.main.async { shared.presentOnMain() }
    }

    private func presentOnMain() {
        focusRecovery.cancelActive()
        guard let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let sessionID = UUID()
        let focus = focusedElement(for: targetPID)
        pasteSession = PasteSession(
            id: sessionID, targetPID: targetPID,
            focusedElement: focus.element, focusCaptureError: focus.error.rawValue
        )
        let displayID = focusedDisplayID(for: targetPID)
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        if NSRunningApplication.runningApplications(withBundleIdentifier: TidyTapProduct.appBundleIdentifier)
            .contains(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == appURL }) {
            if TidyTapLaunchSmoke.current() != nil {
                FileHandle.standardError.write(Data("clipboard-g1: reused exact app\n".utf8))
            }
            TidyTapIPC.postClipboardHistoryToggle(targetPID: targetPID, sessionID: sessionID, displayID: displayID)
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.allowsRunningApplicationSubstitution = false
            var environment = [
                TidyTapIPC.clipboardHistoryModeEnvironmentKey: "1",
                TidyTapIPC.clipboardTargetPIDEnvironmentKey: String(targetPID),
                TidyTapIPC.clipboardSessionEnvironmentKey: sessionID.uuidString
            ]
            if let displayID {
                environment[TidyTapIPC.clipboardDisplayIDEnvironmentKey] = String(displayID)
            }
            if let smoke = TidyTapLaunchSmoke.current() {
                environment[TidyTapLaunchSmoke.enabledKey] = "1"
                environment[TidyTapLaunchSmoke.preferencesSuiteKey] = smoke.preferencesSuite
                if let logPath = ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_G1_LOG_PATH"] {
                    environment["TIDYTAP_CLIPBOARD_G1_LOG_PATH"] = logPath
                }
            }
            configuration.environment = environment
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if TidyTapLaunchSmoke.current() != nil {
                    let exact = app?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == appURL
                    FileHandle.standardError.write(Data("clipboard-g1: launched exact app=\(exact)\n".utf8))
                }
                if let error {
                    FileHandle.standardError.write(Data("clipboard-history: app launch failed \(error)\n".utf8))
                }
            }
        }
    }

    @objc private func pasteRequested(_ notification: Notification) {
        guard let request = TidyTapIPC.clipboardPasteRequest(in: notification),
              let session = pasteSession, session.id == request.sessionID else { return }
        pasteSession = nil
        var lastFocusError: Int32?
        focusRecovery.start(
            id: session.id,
            originalCaptured: session.focusedElement != nil,
            targetIsReady: { self.targetIsReady(for: session.targetPID) },
            inspectFocus: {
                let current = self.focusedElement(for: session.targetPID)
                lastFocusError = current.error.rawValue
                guard current.error == .success else {
                    return current.error == .noValue ? .noValue : .otherError(current.error.rawValue)
                }
                guard let currentElement = current.element else { return .otherError(current.error.rawValue) }
                guard let originalElement = session.focusedElement else { return .different }
                return CFEqual(currentElement, originalElement) ? .original : .different
            },
            paste: {
                self.postPaste(session: session, entryID: request.entryID, formatted: request.formatted)
            },
            completion: { outcome in
                let sessionLabel = session.id.uuidString.prefix(8)
                switch outcome {
                case .pasted(let error, let retries):
                    TidyTapClipboardPasteLog.append(
                        "helperResult session=\(sessionLabel) reason=\(error ?? "pasteEventPosted") " +
                        "focusRetries=\(retries) originalMatched=true currentAX=\(lastFocusError ?? 0)"
                    )
                    TidyTapIPC.postClipboardHistoryPasteResult(sessionID: session.id, error: error)
                case .failed(let reason, let retries, let axError, let originalMatched):
                    TidyTapClipboardPasteLog.append(
                        "helperResult session=\(sessionLabel) reason=\(reason) " +
                        "focusRetries=\(retries) originalMatched=\(originalMatched) " +
                        "captureAX=\(session.focusCaptureError) originalPresent=\(session.focusedElement != nil) " +
                        "originalRoleAX=\(self.roleError(for: session.focusedElement)) " +
                        "currentAX=\(axError ?? lastFocusError ?? 0)"
                    )
                    TidyTapIPC.postClipboardHistoryPasteResult(sessionID: session.id, error: reason)
                case .superseded:
                    TidyTapClipboardPasteLog.append("helperResult session=\(sessionLabel) reason=superseded")
                    TidyTapIPC.postClipboardHistoryPasteResult(sessionID: session.id, error: "superseded")
                }
            }
        )
    }

    private func focusedElement(for processID: pid_t) -> (element: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let application = AXUIElementCreateApplication(processID)
        let error = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, error) }
        let element = value as! AXUIElement
        return (element, error)
    }

    private func roleError(for element: AXUIElement?) -> Int32 {
        guard let element else { return AXError.noValue.rawValue }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value).rawValue
    }

    private func focusedDisplayID(for processID: pid_t) -> CGDirectDisplayID? {
        var windowValue: CFTypeRef?
        let application = AXUIElementCreateApplication(processID)
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = windowValue as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(center, 1, &displayID, &count) == .success,
              count == 1 else { return nil }
        return displayID
    }

    private func targetIsReady(for pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid &&
            NSRunningApplication(processIdentifier: pid)?.isTerminated == false
    }

    private func postPaste(session: PasteSession, entryID: UUID, formatted: Bool) -> String? {
        guard CGPreflightPostEventAccess() else { return "eventUnavailable" }
        let suite = TidyTapLaunchSmoke.current()?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
        guard let store = try? ClipboardHistoryStore(
            directory: TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: suite),
            retention: TidyTapClipboardPolicy.retention,
            maximumEntries: TidyTapClipboardPolicy.maximumEntries,
            maximumBytes: TidyTapClipboardPolicy.maximumBytes,
            maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
        ), let entries = try? store.entries(),
              let entry = entries.first(where: { $0.id == entryID }) else { return "entryUnavailable" }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return "eventUnavailable"
        }
        guard targetIsReady(for: session.targetPID) else { return "targetUnavailable" }
        guard ClipboardPasteboardWriter.write(
            entry.content,
            style: formatted ? .formatted : .plain,
            to: .general
        ) else { return "pasteboardWriteFailed" }
        for event in [down, up] {
            event.flags = .maskCommand
            CGEventTapBackend.markSynthetic(event)
            event.post(tap: .cgSessionEventTap)
        }
        return nil
    }
}
