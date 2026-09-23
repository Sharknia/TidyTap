import AppKit

/// Observes the current pasteboard value while the feature is enabled. macOS
/// does not provide the contents of intermediate copies between two polls.
@MainActor
public final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let onCapture: (ClipboardCapture) -> Void
    private let canRead: () -> Bool
    private let onReadDenied: () -> Void
    private var timer: Timer?
    private var lastSeenChangeCount = 0
    private var isRunning = false

    public init(
        pasteboard: NSPasteboard,
        canRead: @escaping () -> Bool = { true },
        onReadDenied: @escaping () -> Void = {},
        onCapture: @escaping (ClipboardCapture) -> Void
    ) {
        self.pasteboard = pasteboard
        self.canRead = canRead
        self.onReadDenied = onReadDenied
        self.onCapture = onCapture
    }

    public func start() {
        guard !isRunning else { return }
        lastSeenChangeCount = pasteboard.changeCount
        isRunning = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    public func poll() {
        guard isRunning else { return }
        guard canRead() else {
            stop()
            onReadDenied()
            return
        }
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current
        if let capture = ClipboardPasteboardReader.capture(from: pasteboard) {
            onCapture(capture)
        }
    }
}
