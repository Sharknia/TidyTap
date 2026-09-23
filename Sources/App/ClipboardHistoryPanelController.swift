import AppKit
import TidyTapInputEngine

struct ClipboardPasteKeyState {
    private var pendingReverseStyle: Bool?

    mutating func handle(
        type: NSEvent.EventType,
        keyCode: UInt16,
        isRepeat: Bool,
        shiftHeld: Bool
    ) -> (consumed: Bool, reverseStyle: Bool?) {
        guard keyCode == 36 || keyCode == 76 else { return (false, nil) }
        switch type {
        case .keyDown:
            if !isRepeat && pendingReverseStyle == nil {
                pendingReverseStyle = shiftHeld
            }
            return (true, nil)
        case .keyUp:
            guard let pendingReverseStyle else { return (false, nil) }
            self.pendingReverseStyle = nil
            return (true, pendingReverseStyle)
        default:
            return (false, nil)
        }
    }

    mutating func reset() { pendingReverseStyle = nil }
}

@MainActor
final class ClipboardHistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private static let textRowCharacterLimit = 200
    private static let textPreviewCharacterLimit = 20_000
    private static let backgroundSearchThreshold = 1_000_000

    private struct SearchCandidate: Sendable {
        let id: UUID
        let text: String
    }

    private enum SelectionTarget: Sendable {
        case none
        case first
        case id(UUID)
        case row(Int)
    }

    let panel: NSPanel
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let textPreview = NSTextView()
    private let textScroll = NSScrollView()
    private let imagePreview = NSImageView()
    private let footer = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var entries = [ClipboardHistoryEntry]()
    private var filtered = [ClipboardHistoryEntry]()
    private var pasteFormattedByDefault = false
    private var latestCopyTooLarge = false
    private var onPaste: ((ClipboardHistoryEntry, ClipboardTextPasteStyle) -> Void)?
    private var onDelete: ((UUID, Int) -> Void)?
    private var onCancel: ((Bool) -> Void)?
    private var keyMonitor: Any?
    private var pasteKeyState = ClipboardPasteKeyState()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var isFiltering = false

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = String(localized: "Clipboard history")
        panel.titleVisibility = .hidden
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        buildContent()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    var isVisible: Bool { panel.isVisible }
    var selectedEntry: ClipboardHistoryEntry? {
        filtered.indices.contains(tableView.selectedRow) ? filtered[tableView.selectedRow] : nil
    }
    var visibleCount: Int { filtered.count }

    func updateEntries(_ entries: [ClipboardHistoryEntry], latestCopyTooLarge: Bool = false) {
        self.latestCopyTooLarge = latestCopyTooLarge
        self.entries = entries.sorted { $0.copiedAt > $1.copiedAt }
        applyFilter(selection: latestCopyTooLarge ? .none : .first)
    }

    func refreshPreservingSelection(_ entries: [ClipboardHistoryEntry], latestCopyTooLarge: Bool = false) {
        let selectedID = selectedEntry?.id
        self.latestCopyTooLarge = latestCopyTooLarge
        self.entries = entries.sorted { $0.copiedAt > $1.copiedAt }
        applyFilter(selection: selectedID.map(SelectionTarget.id) ?? defaultSearchSelection())
    }

    func refreshAfterDeleting(_ entries: [ClipboardHistoryEntry], previousRow: Int) {
        latestCopyTooLarge = false
        self.entries = entries.sorted { $0.copiedAt > $1.copiedAt }
        applyFilter(selection: .row(previousRow))
    }

    func search(_ query: String) {
        searchField.stringValue = query
        applyFilter(selection: defaultSearchSelection())
    }

    func show(
        entries: [ClipboardHistoryEntry],
        displayID: UInt32?,
        pasteFormattedByDefault: Bool,
        latestCopyTooLarge: Bool,
        onPaste: @escaping (ClipboardHistoryEntry, ClipboardTextPasteStyle) -> Void,
        onDelete: @escaping (UUID, Int) -> Void,
        onCancel: @escaping (Bool) -> Void
    ) {
        self.pasteFormattedByDefault = pasteFormattedByDefault
        self.onPaste = onPaste
        self.onDelete = onDelete
        self.onCancel = onCancel
        pasteKeyState.reset()
        searchField.stringValue = ""
        updateEntries(entries, latestCopyTooLarge: latestCopyTooLarge)
        let focusedScreen = NSScreen.screens.first(where: {
            guard let displayID else { return false }
            return ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })
        if let screen = focusedScreen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func close(restorePreviousApp: Bool = true) {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isFiltering = false
        guard panel.isVisible, let cancel = onCancel else { return }
        onCancel = nil
        onPaste = nil
        onDelete = nil
        pasteKeyState.reset()
        panel.orderOut(nil)
        cancel(restorePreviousApp)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("clipboard.history.row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        if cell.textField == nil {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(false)
            cell.addSubview(icon)
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 30),
                icon.heightAnchor.constraint(equalToConstant: 30),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.imageView = icon
            cell.textField = label
            cell.identifier = identifier
        }
        switch filtered[row].content {
        case .text(let plain, _, _):
            cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            let summary = plain.prefix(Self.textRowCharacterLimit)
            let singleLine = String(summary).replacingOccurrences(of: "\n", with: " ")
            cell.textField?.stringValue = summary.endIndex == plain.endIndex ? singleLine : singleLine + "…"
        case .image(let data, _):
            cell.imageView?.image = NSImage(data: data)
            cell.textField?.stringValue = String(localized: "Image")
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(selection: defaultSearchSelection(), debounce: true)
    }

    private func defaultSearchSelection() -> SelectionTarget {
        latestCopyTooLarge && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .none : .first
    }

    func windowDidResignKey(_ notification: Notification) {
        close(restorePreviousApp: false)
    }

    private func buildContent() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        panel.contentView = root

        searchField.placeholderString = String(localized: "Search copied text…")
        searchField.delegate = self
        searchField.setAccessibilityLabel(String(localized: "Search copied text"))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard.history.content"))
        column.width = 260
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClick(_:))
        tableView.setAccessibilityLabel(String(localized: "Clipboard entries"))
        let listScroll = NSScrollView()
        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(listScroll)

        textPreview.isEditable = false
        textPreview.isSelectable = true
        textPreview.drawsBackground = false
        textPreview.font = .systemFont(ofSize: 14)
        textPreview.setAccessibilityLabel(String(localized: "Copied text preview"))
        textScroll.documentView = textPreview
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .noBorder
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(textScroll)

        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.setAccessibilityLabel(String(localized: "Copied image preview"))
        imagePreview.translatesAutoresizingMaskIntoConstraints = false
        imagePreview.isHidden = true
        root.addSubview(imagePreview)

        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        deleteButton.title = String(localized: "Delete")
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            searchField.heightAnchor.constraint(equalToConstant: 32),
            listScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            listScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            listScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            listScroll.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.36),
            textScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 16),
            textScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            textScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            imagePreview.leadingAnchor.constraint(equalTo: textScroll.leadingAnchor),
            imagePreview.trailingAnchor.constraint(equalTo: textScroll.trailingAnchor),
            imagePreview.topAnchor.constraint(equalTo: textScroll.topAnchor),
            imagePreview.bottomAnchor.constraint(equalTo: textScroll.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            footer.heightAnchor.constraint(equalToConstant: 20),
            deleteButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            deleteButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    private func applyFilter(selection: SelectionTarget, debounce: Bool = false) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = nil
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            isFiltering = false
            finishFilter(entries, selection: selection)
            return
        }
        let candidates = entries.compactMap { entry -> SearchCandidate? in
            guard case .text(let plain, _, _) = entry.content else { return nil }
            return SearchCandidate(id: entry.id, text: plain)
        }
        let bytes = candidates.reduce(0) { $0 + $1.text.utf8.count }
        if bytes <= Self.backgroundSearchThreshold {
            isFiltering = false
            let matching = Set(candidates.filter { $0.text.localizedCaseInsensitiveContains(query) }.map(\.id))
            finishFilter(entries.filter { matching.contains($0.id) }, selection: selection)
            return
        }

        isFiltering = true
        filtered = []
        tableView.reloadData()
        updatePreview()
        searchTask = Task.detached(priority: .userInitiated) { [candidates, query, selection, generation, debounce, weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            var matching = Set<UUID>()
            for candidate in candidates {
                if Task.isCancelled { return }
                if candidate.text.localizedCaseInsensitiveContains(query) { matching.insert(candidate.id) }
            }
            await MainActor.run { [weak self] in
                guard let self, self.searchGeneration == generation else { return }
                self.searchTask = nil
                self.isFiltering = false
                self.finishFilter(self.entries.filter { matching.contains($0.id) }, selection: selection)
            }
        }
    }

    private func finishFilter(_ results: [ClipboardHistoryEntry], selection: SelectionTarget) {
        filtered = results
        tableView.reloadData()
        if !filtered.isEmpty {
            let row: Int
            switch selection {
            case .none:
                tableView.deselectAll(nil)
                updatePreview()
                return
            case .first:
                row = 0
            case .id(let id):
                row = filtered.firstIndex(where: { $0.id == id }) ?? 0
            case .row(let previous):
                row = max(0, min(previous, filtered.count - 1))
            }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        updatePreview()
    }

    private func updatePreview() {
        guard filtered.indices.contains(tableView.selectedRow) else {
            deleteButton.isEnabled = false
            footer.stringValue = ""
            imagePreview.isHidden = true
            textScroll.isHidden = false
            textPreview.string = isFiltering
                ? String(localized: "Searching copied text…")
                : latestCopyTooLarge && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? String(localized: "The latest copy exceeded the 10 MiB item limit and was not saved. Select another item from the list.")
                    : entries.isEmpty
                        ? String(localized: "No copied items yet")
                        : String(localized: "No search results")
            return
        }
        deleteButton.isEnabled = true
        switch filtered[tableView.selectedRow].content {
        case .text(let plain, _, _):
            footer.stringValue = pasteFormattedByDefault
                ? String(localized: "Paste with formatting ↵  ·  Paste without formatting ⇧↵")
                : String(localized: "Paste without formatting ↵  ·  Paste with formatting ⇧↵")
            imagePreview.isHidden = true
            textScroll.isHidden = false
            let preview = plain.prefix(Self.textPreviewCharacterLimit)
            textPreview.string = preview.endIndex == plain.endIndex ? plain : "\(preview)\n…"
        case .image(let data, _):
            footer.stringValue = String(localized: "Paste image ↵")
            imagePreview.image = NSImage(data: data)
            imagePreview.isHidden = false
            textScroll.isHidden = true
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, panel.isKeyWindow else { return event }
        if event.type == .keyDown,
           let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return event
        }
        let pasteKey = pasteKeyState.handle(
            type: event.type,
            keyCode: event.keyCode,
            isRepeat: event.isARepeat,
            shiftHeld: event.modifierFlags.contains(.shift)
        )
        if let reverseStyle = pasteKey.reverseStyle {
            paste(reverseStyle: reverseStyle)
        }
        if pasteKey.consumed { return nil }
        guard event.type == .keyDown else { return event }
        switch event.keyCode {
        case 53:
            close()
            return nil
        case 125, 126:
            guard !filtered.isEmpty else { return nil }
            let delta = event.keyCode == 125 ? 1 : -1
            let next = min(max(tableView.selectedRow + delta, 0), filtered.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return nil
        default:
            return event
        }
    }

    @objc private func doubleClick(_ sender: NSTableView) {
        pasteKeyState.reset()
        paste(reverseStyle: false)
    }

    @objc private func deleteSelected(_ sender: NSButton) {
        guard let selectedEntry else { return }
        onDelete?(selectedEntry.id, tableView.selectedRow)
    }

    private func paste(reverseStyle: Bool) {
        guard filtered.indices.contains(tableView.selectedRow) else { return }
        pasteKeyState.reset()
        let entry = filtered[tableView.selectedRow]
        let formatted = pasteFormattedByDefault != reverseStyle
        let action = onPaste
        onCancel = nil
        onDelete = nil
        onPaste = nil
        panel.orderOut(nil)
        action?(entry, formatted ? .formatted : .plain)
    }
}
