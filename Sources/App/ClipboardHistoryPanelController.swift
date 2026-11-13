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

struct ClipboardPaneKeyState {
    private var held = Set<UInt16>()
    mutating func handle(_ event: NSEvent) -> (consumed: Bool, pane: ClipboardHistoryPanelController.Pane?) {
        if event.type == .keyUp { return (held.remove(event.keyCode) != nil, nil) }
        guard event.type == .keyDown else { return (false, nil) }
        if held.contains(event.keyCode) { return (true, nil) }
        guard !event.isARepeat,
              event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
              let character = event.charactersIgnoringModifiers, character == "1" || character == "2" else { return (false, nil) }
        held.insert(event.keyCode)
        return (true, character == "1" ? .history : .pinned)
    }
    mutating func reject(_ keyCode: UInt16) { held.remove(keyCode) }
    mutating func reset() { held.removeAll() }
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
        case preserving(UUID?, Int)
    }

    typealias LibrarySnapshot = ClipboardLibrarySnapshot
    enum Pane: Int { case history, pinned }
    private struct PaneState { var query: String; var filter: Int; var selection: UUID?; var scroll: NSPoint }
    private(set) var pane: Pane = .history
    private var paneStates = [Pane: PaneState]()
    private var library = LibrarySnapshot(entries: [], historyOrder: [], pinnedOrder: [])
    private let localizationBundle: Bundle
    private let scopeControl = NSSegmentedControl()
    private let pinButton = NSButton()
    private var displaySession = UUID()
    private var pendingMutation: UUID?
    private var mutationError: String?
    private var pasteError: String?
    private var pendingScroll: NSPoint?
    private var paneKeyState = ClipboardPaneKeyState()
    private var onSetPinned: ((UUID, Bool, @escaping (Result<LibrarySnapshot, Error>) -> Void) -> Void)?
    private var onDeleteHistory: ((UUID, @escaping (Result<LibrarySnapshot, Error>) -> Void) -> Void)?
    let panel: NSPanel
    private(set) var pasteScreen: NSScreen?
    private let searchField = NSSearchField()
    private let contentFilter = NSSegmentedControl()
    private let listScroll = NSScrollView()
    private let tableView = NSTableView()
    private let textPreview = NSTextView()
    private let textScroll = NSScrollView()
    private let imagePreview = NSImageView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let previousAttempt = NSTextField(labelWithString: "")
    private var previousAttemptHeight: NSLayoutConstraint!
    private let footer = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var entries = [ClipboardHistoryEntry]()
    private var filtered = [ClipboardHistoryEntry]()
    private var pasteFormattedByDefault = false
    private var latestCopyTooLarge = false
    private var onPaste: ((ClipboardHistoryEntry, ClipboardTextPasteStyle) -> Void)?
    private var onCancel: ((Bool) -> Void)?
    private var keyMonitor: Any?
    private var pasteKeyState = ClipboardPasteKeyState()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var isFiltering = false
    private var inFlightSelection: SelectionTarget?

    init(localizationBundle: Bundle = .main) {
        self.localizationBundle = localizationBundle
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = text("Clipboard history")
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

    private func text(_ key: String) -> String { localizationBundle.localizedString(forKey: key, value: key, table: nil) }

    func setPreviousAttempt(_ message: String?) { pasteError = message; updateErrorLabel() }
    private func updateErrorLabel() {
        let messages = [pasteError, mutationError].compactMap { $0 }
        previousAttempt.stringValue = messages.joined(separator: "\n")
        previousAttempt.toolTip = previousAttempt.stringValue
        previousAttempt.isHidden = messages.isEmpty
        previousAttemptHeight.constant = CGFloat(messages.count * 18)
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

    private func valid(_ snapshot: LibrarySnapshot) -> Bool {
        let ids = Set(snapshot.entries.map(\.id))
        return ids.count == snapshot.entries.count && Set(snapshot.historyOrder).count == snapshot.historyOrder.count
            && Set(snapshot.pinnedOrder).count == snapshot.pinnedOrder.count
            && ids == Set(snapshot.historyOrder).union(snapshot.pinnedOrder)
    }
    private func loadPaneEntries() {
        let order = pane == .history ? library.historyOrder : library.pinnedOrder
        let map = Dictionary(uniqueKeysWithValues: library.entries.map { ($0.id, $0) })
        entries = order.compactMap { map[$0] }
    }
    func updateEntries(_ snapshot: LibrarySnapshot, latestCopyTooLarge: Bool = false) {
        guard valid(snapshot) else { mutationError = text("Could not update clipboard library."); updateErrorLabel(); return }
        library = snapshot; self.latestCopyTooLarge = latestCopyTooLarge; loadPaneEntries()
        if !panel.isVisible {
            let containsImage = entries.contains { if case .image = $0.content { return true }; return false }
            panel.setContentSize(NSSize(width: 800, height: min(504, max(containsImage ? 424 : 304, 204 + CGFloat(min(entries.count, 7)) * 42))))
        }
        applyFilter(selection: defaultSearchSelection())
    }
    func refreshPreservingSelection(_ snapshot: LibrarySnapshot, latestCopyTooLarge: Bool = false) {
        guard valid(snapshot) else { mutationError = text("Could not update clipboard library."); updateErrorLabel(); return }
        let selection = isFiltering ? (inFlightSelection ?? .preserving(selectedEntry?.id, tableView.selectedRow))
            : .preserving(selectedEntry?.id, tableView.selectedRow)
        if pendingScroll == nil { pendingScroll = listScroll.contentView.bounds.origin }
        library = snapshot; self.latestCopyTooLarge = latestCopyTooLarge; loadPaneEntries()
        applyFilter(selection: selection)
    }

    @discardableResult
    func switchPane(_ next: Pane) -> Bool {
        guard next != pane else { return true }
        let responder = panel.firstResponder
        let editor = responder as? NSTextView
        if panel.isVisible && (!panel.makeFirstResponder(nil) || editor?.hasMarkedText() == true) {
            scopeControl.selectedSegment = pane.rawValue
            if let responder { panel.makeFirstResponder(responder) }
            return false
        }
        let currentID: UUID?
        if isFiltering, let inFlightSelection {
            switch inFlightSelection {
            case .preserving(let id, _): currentID = id
            case .id(let id): currentID = id
            default: currentID = nil
            }
        } else { currentID = selectedEntry?.id }
        paneStates[pane] = PaneState(query: searchField.stringValue, filter: contentFilter.selectedSegment,
                                    selection: currentID, scroll: pendingScroll ?? listScroll.contentView.bounds.origin)
        searchGeneration &+= 1; searchTask?.cancel(); searchTask = nil; pasteKeyState.reset()
        pane = next; scopeControl.selectedSegment = next.rawValue
        let state = paneStates[next]
        searchField.stringValue = state?.query ?? ""; contentFilter.selectedSegment = state?.filter ?? 0
        searchField.isEnabled = !imagesOnly; loadPaneEntries()
        pendingScroll = state?.scroll ?? .zero
        let candidate = state?.selection ?? currentID
        applyFilter(selection: candidate.map(SelectionTarget.id) ?? defaultSearchSelection())
        if panel.isVisible { panel.makeFirstResponder(imagesOnly ? contentFilter : searchField) }
        return true
    }
    @objc private func changePane(_ sender: NSSegmentedControl) { _ = switchPane(Pane(rawValue: sender.selectedSegment) ?? .history) }

    func search(_ query: String) {
        pendingScroll = nil
        searchField.stringValue = query
        applyFilter(selection: defaultSearchSelection())
    }

    func show(
        snapshot: LibrarySnapshot,
        displayID: UInt32?,
        pasteFormattedByDefault: Bool,
        latestCopyTooLarge: Bool,
        onPaste: @escaping (ClipboardHistoryEntry, ClipboardTextPasteStyle) -> Void,
        onSetPinned: @escaping (UUID, Bool, @escaping (Result<LibrarySnapshot, Error>) -> Void) -> Void,
        onDeleteHistory: @escaping (UUID, @escaping (Result<LibrarySnapshot, Error>) -> Void) -> Void,
        onCancel: @escaping (Bool) -> Void
    ) -> Bool {
        guard valid(snapshot) else {
            close(restorePreviousApp: false); onPasteInvalidSnapshot(); return false
        }
        displaySession = UUID(); pendingMutation = nil; mutationError = nil; pendingScroll = nil; inFlightSelection = nil
        pane = .history; paneStates = [:]; scopeControl.selectedSegment = 0
        self.pasteFormattedByDefault = pasteFormattedByDefault
        self.onPaste = onPaste
        self.onSetPinned = onSetPinned
        self.onDeleteHistory = onDeleteHistory
        self.onCancel = onCancel
        pasteKeyState.reset(); paneKeyState.reset()
        contentFilter.selectedSegment = 0
        searchField.isEnabled = true
        searchField.stringValue = ""
        updateEntries(snapshot, latestCopyTooLarge: latestCopyTooLarge)
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
        updateErrorLabel()
        return true
    }
    private func onPasteInvalidSnapshot() { library = .init(entries: [], historyOrder: [], pinnedOrder: []); entries = []; filtered = []; onPaste = nil; onCancel = nil; onSetPinned = nil; onDeleteHistory = nil; pasteKeyState.reset(); paneKeyState.reset() }

    func close(restorePreviousApp: Bool = true) {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isFiltering = false; pendingScroll = nil; inFlightSelection = nil
        let cancel = onCancel
        onCancel = nil; onPaste = nil
        onSetPinned = nil; onDeleteHistory = nil; pendingMutation = nil
        displaySession = UUID(); paneKeyState.reset(); pasteKeyState.reset()
        panel.orderOut(nil)
        cancel?(restorePreviousApp)
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
            let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: text("Pinned")) ?? NSImage())
            pin.identifier = .init("clipboard.row.pin"); pin.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(pin)
            NSLayoutConstraint.activate([
                pin.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 28),
                pin.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -5),
                pin.widthAnchor.constraint(equalToConstant: 10), pin.heightAnchor.constraint(equalToConstant: 10),
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
        cell.subviews.first { $0.identifier?.rawValue == "clipboard.row.pin" }?.isHidden = !library.pinnedOrder.contains(filtered[row].id)
        switch filtered[row].content {
        case .text(let plain, _, _):
            cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            let summary = plain.prefix(Self.textRowCharacterLimit)
            let singleLine = String(summary).replacingOccurrences(of: "\n", with: " ")
            cell.textField?.stringValue = summary.endIndex == plain.endIndex ? singleLine : singleLine + "…"
        case .image(let data, _):
            cell.imageView?.image = NSImage(data: data)
            cell.textField?.stringValue = text("Image")
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

        searchField.placeholderString = text("Search copied text…")
        searchField.delegate = self
        searchField.setAccessibilityLabel(text("Search copied text"))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)
        scopeControl.segmentCount = 2; scopeControl.segmentDistribution = .fillEqually
        scopeControl.setLabel(text("Recent history ⌘1"), forSegment: 0)
        scopeControl.setLabel(text("Pinboard ⌘2"), forSegment: 1)
        scopeControl.selectedSegment = 0; scopeControl.trackingMode = .selectOne
        scopeControl.identifier = .init("clipboard.history.scope")
        scopeControl.target = self; scopeControl.action = #selector(changePane(_:))
        scopeControl.setAccessibilityLabel(text("Clipboard library"))
        scopeControl.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(scopeControl)

        contentFilter.identifier = .init("clipboard.history.contentFilter")
        contentFilter.segmentCount = 2
        contentFilter.segmentDistribution = .fillEqually
        if #available(macOS 26.0, *) { contentFilter.borderShape = .capsule }
        contentFilter.setLabel(text("All"), forSegment: 0)
        contentFilter.setLabel(text("Images"), forSegment: 1)
        contentFilter.trackingMode = .selectOne
        contentFilter.selectedSegment = 0
        contentFilter.target = self
        contentFilter.action = #selector(changeContentFilter(_:))
        contentFilter.setAccessibilityLabel(text("Clipboard content filter"))
        contentFilter.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentFilter)
        searchField.toolTip = text("Text search is available in All")

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
        tableView.setAccessibilityLabel(text("Clipboard entries"))
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
        textPreview.setAccessibilityLabel(text("Copied text preview"))
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
        imagePreview.setAccessibilityLabel(text("Copied image preview"))
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

        previousAttempt.font = .systemFont(ofSize: 11)
        previousAttempt.textColor = .secondaryLabelColor
        previousAttempt.lineBreakMode = .byTruncatingTail
        previousAttempt.usesSingleLineMode = false
        previousAttempt.maximumNumberOfLines = 2
        previousAttempt.translatesAutoresizingMaskIntoConstraints = false
        previousAttempt.isHidden = true
        root.addSubview(previousAttempt)
        previousAttemptHeight = previousAttempt.heightAnchor.constraint(equalToConstant: 0)

        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        footer.usesSingleLineMode = true
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        deleteButton.title = text("Delete history item")
        deleteButton.isBordered = false
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(deleteButton)
        pinButton.identifier = .init("clipboard.history.pin")
        pinButton.title = text("Pin to pinboard"); pinButton.isBordered = false
        pinButton.font = .systemFont(ofSize: 11); pinButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        pinButton.target = self; pinButton.action = #selector(changePin(_:))
        pinButton.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(pinButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentFilter.leadingAnchor, constant: -12),
            scopeControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scopeControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scopeControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scopeControl.heightAnchor.constraint(equalToConstant: 36),
            searchField.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 8),
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
            footerSeparator.topAnchor.constraint(equalTo: previousAttempt.topAnchor, constant: -10),
            previousAttempt.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            previousAttempt.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            previousAttempt.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            previousAttemptHeight,
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 18),
            pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            pinButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    private func applyFilter(selection: SelectionTarget, debounce: Bool = false) {
        inFlightSelection = selection
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
        defer { inFlightSelection = nil; pendingScroll = nil }
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
            case .preserving(let id, let previous):
                if let id, let found = filtered.firstIndex(where: { $0.id == id }) { row = found }
                else if preventsAutomaticSelection { tableView.deselectAll(nil); updatePreview(); return }
                else { row = max(0, min(previous, filtered.count - 1)) }
            case .row(let previous):
                row = max(0, min(previous, filtered.count - 1))
            }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        if let point = pendingScroll {
            pendingScroll = nil
            listScroll.contentView.scroll(to: point); listScroll.reflectScrolledClipView(listScroll.contentView)
            if tableView.selectedRow >= 0 && !tableView.visibleRect.intersects(tableView.rect(ofRow: tableView.selectedRow)) {
                tableView.scrollRowToVisible(tableView.selectedRow)
            }
        }
        updatePreview()
    }

    private func updatePreview() {
        guard filtered.indices.contains(tableView.selectedRow) else {
            deleteButton.isEnabled = false; pinButton.isEnabled = false; deleteButton.isHidden = pane == .pinned
            footer.stringValue = ""
            imagePreview.isHidden = true
            textScroll.isHidden = true
            textPreview.string = pane == .pinned && entries.isEmpty ? text("Pinboard is empty. Pin an item from recent history.") : isFiltering
                ? text("Searching copied text…")
                : preventsAutomaticSelection
                    ? text("The latest copy exceeded the 10 MiB item limit and was not saved. Select another item from the list.")
                    : entries.isEmpty
                        ? text("No copied items yet")
                        : imagesOnly
                            ? text("No saved images")
                        : text("No search results")
            emptyStateLabel.stringValue = textPreview.string
            emptyStateLabel.isHidden = false
            return
        }
        deleteButton.isHidden = pane == .pinned
        deleteButton.isEnabled = pendingMutation == nil; pinButton.isEnabled = pendingMutation == nil
        let pinned = library.pinnedOrder.contains(filtered[tableView.selectedRow].id)
        pinButton.title = text(pinned ? "Unpin" : "Pin to pinboard")
        emptyStateLabel.isHidden = true
        switch filtered[tableView.selectedRow].content {
        case .text(let plain, _, _):
            footer.stringValue = pasteFormattedByDefault
                ? text("Paste formatted ↵  ·  Plain ⇧↵")
                : text("Paste plain ↵  ·  Formatted ⇧↵")
            imagePreview.isHidden = true
            textScroll.isHidden = false
            let preview = plain.prefix(Self.textPreviewCharacterLimit)
            textPreview.string = preview.endIndex == plain.endIndex ? plain : "\(preview)\n…"
        case .image(let data, _):
            footer.stringValue = text("Paste image ↵")
            imagePreview.image = NSImage(data: data)
            imagePreview.isHidden = false
            textScroll.isHidden = true
        }
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, panel.isKeyWindow else { return event }
        let command = paneKeyState.handle(event)
        if let target = command.pane, !switchPane(target) { paneKeyState.reject(event.keyCode); return event }
        if command.consumed { return nil }
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
        guard pane == .history, let entry = selectedEntry, let action = onDeleteHistory else { return }
        mutate { completion in action(entry.id, completion) }
    }
    @objc private func changePin(_ sender: NSButton) {
        guard let entry = selectedEntry, let action = onSetPinned else { return }
        let desired = !library.pinnedOrder.contains(entry.id)
        mutate { completion in action(entry.id, desired, completion) }
    }
    private func mutate(_ action: (@escaping (Result<LibrarySnapshot, Error>) -> Void) -> Void) {
        guard pendingMutation == nil else { return }
        let request = UUID(), session = displaySession
        pendingMutation = request; mutationError = nil; updateErrorLabel(); updatePreview()
        action { [weak self] result in
            guard let self, self.displaySession == session, self.pendingMutation == request else { return }
            self.pendingMutation = nil
            switch result {
            case .success(let snapshot): self.refreshPreservingSelection(snapshot, latestCopyTooLarge: self.latestCopyTooLarge)
            case .failure: self.mutationError = self.text("Could not update clipboard library.")
            }
            self.updateErrorLabel(); self.updatePreview()
        }
    }

    private func paste(reverseStyle: Bool) {
        guard filtered.indices.contains(tableView.selectedRow) else { return }
        searchGeneration &+= 1; searchTask?.cancel(); searchTask = nil
        isFiltering = false; pendingScroll = nil; inFlightSelection = nil
        pasteKeyState.reset()
        let entry = filtered[tableView.selectedRow]
        let formatted = pasteFormattedByDefault != reverseStyle
        let action = onPaste
        pasteScreen = panel.screen
        onCancel = nil
        onSetPinned = nil; onDeleteHistory = nil; pendingMutation = nil; displaySession = UUID(); paneKeyState.reset()
        onPaste = nil
        panel.orderOut(nil)
        action?(entry, formatted ? .formatted : .plain)
    }
}
