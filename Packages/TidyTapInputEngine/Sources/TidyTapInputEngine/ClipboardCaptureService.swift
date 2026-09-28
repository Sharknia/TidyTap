import AppKit

/// Connects the enabled pasteboard monitor to the local history store.
@MainActor
public final class ClipboardCaptureService {
    public enum CaptureError: Error {
        case readDenied
        case continuousAccessRequired
    }

    private let store: ClipboardHistoryStore
    private let pasteboard: NSPasteboard
    private let onFailure: (Error) -> Void
    private let onCaptured: (ClipboardHistoryEntry) -> Void
    private let canRead: () -> Bool
    private lazy var monitor = ClipboardMonitor(
        pasteboard: pasteboard,
        canRead: canRead,
        onReadDenied: { [weak self] in self?.onFailure(CaptureError.readDenied) },
        onCapture: { [weak self] capture in self?.save(capture) }
    )

    public init(
        store: ClipboardHistoryStore,
        pasteboard: NSPasteboard,
        canRead: @escaping () -> Bool = { true },
        onCaptured: @escaping (ClipboardHistoryEntry) -> Void = { _ in },
        onFailure: @escaping (Error) -> Void
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.canRead = canRead
        self.onCaptured = onCaptured
        self.onFailure = onFailure
    }

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }
    public func poll() { monitor.poll() }

    private func save(_ capture: ClipboardCapture) {
        do {
            let entry = try store.add(capture.content)
            onCaptured(entry)
        } catch ClipboardHistoryStore.StoreError.itemTooLarge {
            // Keep capturing later copies, but let the next history opening
            // explain why the current clipboard item is absent.
            do {
                try store.recordOversizedCopy(changeCount: capture.changeCount)
            } catch {
                monitor.stop()
                onFailure(error)
            }
        } catch {
            monitor.stop()
            onFailure(error)
        }
    }
}
