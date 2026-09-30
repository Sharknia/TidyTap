import AppKit
import TidyTapInputEngine

private final class ClipboardHistoryRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 8, yRadius: 8).fill()
    }
}

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
    private let contentFilter = NSSegmentedControl()
    private let listScroll = NSScrollView()
    private let tableView = NSTableView()
    private let textPreview = NSTextView()
    private let textScroll = NSScrollView()
    private let imagePreview = NSImageView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = String(localized: "Clipboard history")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        buildContent()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    var isVisible: Bool { panel.isVisible }
    var searchQuery: String { imagesOnly ? "" : searchField.stringValue }
    private var imagesOnly: Bool { contentFilter.selectedSegment == 1 }
    private var effectiveQuery: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var preventsAutomaticSelection: Bool { latestCopyTooLarge && effectiveQuery.isEmpty }
    var selectedEntry: ClipboardHistoryEntry? {
        filtered.indices.contains(tableView.selectedRow) ? filtered[tableView.selectedRow] : nil
    }
    var visibleCount: Int { filtered.count }
    func sourcePosition(for id: UUID) -> (index: Int, count: Int) {
        (entries.firstIndex(where: { $0.id == id }) ?? -1, entries.count)
    }

    func updateEntries(_ entries: [ClipboardHistoryEntry], latestCopyTooLarge: Bool = false) {
        self.latestCopyTooLarge = latestCopyTooLarge
        self.entries = entries.sorted { $0.copiedAt > $1.copiedAt }
        if !panel.isVisible {
            let containsImage = entries.contains {
                if case .image = $0.content { return true }
                return false
            }
            panel.setContentSize(NSSize(
                width: 800,
                height: min(460, max(containsImage ? 380 : 260, 160 + CGFloat(min(entries.count, 7)) * 42))
            ))
        }
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
        contentFilter.selectedSegment = 0
        searchField.isEnabled = true
        searchField.stringValue = ""
        updateEntries(entries, latestCopyTooLarge: latestCopyTooLarge)
        let focusedScreen = NSScreen.screens.first(where: {
            guard let displayID else { return false }
            return ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })
        if let screen = focusedScreen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            panel.setContentSize(NSSize(
                width: min(800, max(480, screen.visibleFrame.width - 24)),
                height: min(panel.contentView?.bounds.height ?? 460, screen.visibleFrame.height - 24)
            ))
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
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
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            cell.addSubview(icon)
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.usesSingleLineMode = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 26),
                icon.heightAnchor.constraint(equalToConstant: 26),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            label.font = .systemFont(ofSize: 13, weight: .medium)
            cell.imageView = icon
            cell.textField = label
            cell.identifier = identifier
        }
        switch filtered[row].content {
        case .text(let plain, _, _):
            cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipboardHistoryRowView()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(selection: defaultSearchSelection(), debounce: true)
    }

    @objc private func changeContentFilter(_ sender: NSSegmentedControl) {
        let selectedID = selectedEntry?.id
        panel.endEditing(for: searchField)
        pasteKeyState.reset()
        searchField.isEnabled = !imagesOnly
        applyFilter(selection: selectedID.map(SelectionTarget.id) ?? defaultSearchSelection())
        panel.makeFirstResponder(imagesOnly ? contentFilter : searchField)
    }

    private func defaultSearchSelection() -> SelectionTarget {
        preventsAutomaticSelection ? .none : .first
    }

    func windowDidResignKey(_ notification: Notification) {
        close(restorePreviousApp: false)
    }

    func windowDidResize(_ notification: Notification) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let width = listScroll.contentSize.width
        if width > 0 { tableView.tableColumns.first?.width = width }
    }

    private func buildContent() {
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .withinWindow
        root.state = .active
        panel.contentView = root

        func separator() -> NSBox {
            let view = NSBox()
            view.boxType = .separator
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            return view
        }
        let searchSeparator = separator()
        let columnSeparator = separator()
        let footerSeparator = separator()

        searchField.placeholderString = String(localized: "Search copied text…")
        searchField.delegate = self
        searchField.setAccessibilityLabel(String(localized: "Search copied text"))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        contentFilter.segmentCount = 2
        contentFilter.setLabel(String(localized: "All"), forSegment: 0)
        contentFilter.setLabel(String(localized: "Images"), forSegment: 1)
        contentFilter.trackingMode = .selectOne
        contentFilter.selectedSegment = 0
        contentFilter.target = self
        contentFilter.action = #selector(changeContentFilter(_:))
        contentFilter.setAccessibilityLabel(String(localized: "Clipboard content filter"))
        contentFilter.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentFilter)
        searchField.toolTip = String(localized: "Text search is available in All")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard.history.content"))
        column.width = 260
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClick(_:))
        tableView.setAccessibilityLabel(String(localized: "Clipboard entries"))
        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.drawsBackground = false
        listScroll.borderType = .noBorder
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(listScroll)

        textPreview.isEditable = false
        textPreview.isSelectable = true
        textPreview.drawsBackground = false
        textPreview.font = .systemFont(ofSize: 14)
        textPreview.textContainerInset = NSSize(width: 8, height: 8)
        textPreview.setAccessibilityLabel(String(localized: "Copied text preview"))
        textScroll.documentView = textPreview
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.drawsBackground = false
        textScroll.borderType = .noBorder
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(textScroll)

        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imagePreview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imagePreview.setAccessibilityLabel(String(localized: "Copied image preview"))
        imagePreview.translatesAutoresizingMaskIntoConstraints = false
        imagePreview.isHidden = true
        root.addSubview(imagePreview)

        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateLabel.maximumNumberOfLines = 0
        emptyStateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyStateLabel)

        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        footer.usesSingleLineMode = true
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        deleteButton.title = String(localized: "Delete")
        deleteButton.isBordered = false
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentFilter.leadingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 32),
            contentFilter.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            contentFilter.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            contentFilter.widthAnchor.constraint(equalToConstant: 140),
            searchSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            searchSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            searchSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            searchSeparator.heightAnchor.constraint(equalToConstant: 1),
            listScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            listScroll.topAnchor.constraint(equalTo: searchSeparator.bottomAnchor, constant: 6),
            listScroll.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor, constant: -6),
            listScroll.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.38),
            columnSeparator.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 10),
            columnSeparator.topAnchor.constraint(equalTo: searchSeparator.bottomAnchor),
            columnSeparator.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor),
            columnSeparator.widthAnchor.constraint(equalToConstant: 1),
            textScroll.leadingAnchor.constraint(equalTo: columnSeparator.trailingAnchor, constant: 12),
            textScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            textScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            imagePreview.leadingAnchor.constraint(equalTo: textScroll.leadingAnchor),
            imagePreview.trailingAnchor.constraint(equalTo: textScroll.trailingAnchor),
            imagePreview.topAnchor.constraint(equalTo: textScroll.topAnchor),
            imagePreview.bottomAnchor.constraint(equalTo: textScroll.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: textScroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: textScroll.centerYAnchor),
            emptyStateLabel.widthAnchor.constraint(equalTo: textScroll.widthAnchor, constant: -32),
            footerSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerSeparator.topAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 18),
            deleteButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    private func applyFilter(selection: SelectionTarget, debounce: Bool = false) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = nil
        if imagesOnly {
            isFiltering = false
            finishFilter(entries.filter {
                if case .image = $0.content { return true }
                return false
            }, selection: selection)
            return
        }
        let query = effectiveQuery
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
                if preventsAutomaticSelection && !filtered.contains(where: { $0.id == id }) {
                    tableView.deselectAll(nil)
                    updatePreview()
                    return
                }
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
            textScroll.isHidden = true
            textPreview.string = isFiltering
                ? String(localized: "Searching copied text…")
                : preventsAutomaticSelection
                    ? String(localized: "The latest copy exceeded the 10 MiB item limit and was not saved. Select another item from the list.")
                    : entries.isEmpty
                        ? String(localized: "No copied items yet")
                        : imagesOnly
                            ? String(localized: "No saved images")
                        : String(localized: "No search results")
            emptyStateLabel.stringValue = textPreview.string
            emptyStateLabel.isHidden = false
            return
        }
        deleteButton.isEnabled = true
        emptyStateLabel.isHidden = true
        switch filtered[tableView.selectedRow].content {
        case .text(let plain, _, _):
            footer.stringValue = pasteFormattedByDefault
                ? String(localized: "Paste formatted ↵  ·  Plain ⇧↵")
                : String(localized: "Paste plain ↵  ·  Formatted ⇧↵")
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
