import AppKit
import TidyTapInputEngine
import XCTest

@MainActor
final class SettingsViewControllerTests: XCTestCase {
    func testShortcutRecorderRequiresStartAndCanRestartAfterLosingFocus() throws {
        let recorder = ClipboardShortcutRecorder(
            prompt: "Press", inactivePrompt: "Click Start", invalidPrompt: "Invalid",
            startTitle: "Start", retryTitle: "Again"
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 88),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = recorder
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8
        ))
        recorder.keyDown(with: key)
        XCTAssertNil(recorder.shortcut)
        XCTAssertEqual(recorder.statusText, "Click Start")

        recorder.startButton.performClick(nil)
        XCTAssertTrue(recorder.isCapturing)
        let modifiers = try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: [.option], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58
        ))
        recorder.flagsChanged(with: modifiers)
        XCTAssertEqual(recorder.statusText, "⌥…")
        recorder.keyDown(with: key)
        XCTAssertEqual(recorder.statusText, "⌥C")
        XCTAssertEqual(recorder.shortcut?.keyCode, 8)
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(recorder.startButton.title, "Again")

        recorder.startButton.performClick(nil)
        XCTAssertNil(recorder.shortcut)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(recorder.statusText, "Click Start")
        recorder.keyDown(with: key)
        XCTAssertNil(recorder.shortcut)
        recorder.startButton.performClick(nil)
        recorder.keyDown(with: key)
        XCTAssertEqual(recorder.shortcut?.keyCode, 8)
    }

    func testClipboardEnterPastesOnlyAfterReleaseAndNeverRepeats() {
        var state = ClipboardPasteKeyState()
        let down = state.handle(type: .keyDown, keyCode: 36, isRepeat: false, shiftHeld: true)
        XCTAssertTrue(down.consumed)
        XCTAssertNil(down.reverseStyle)
        let repeated = state.handle(type: .keyDown, keyCode: 36, isRepeat: true, shiftHeld: true)
        XCTAssertTrue(repeated.consumed)
        XCTAssertNil(repeated.reverseStyle)
        let up = state.handle(type: .keyUp, keyCode: 36, isRepeat: false, shiftHeld: false)
        XCTAssertTrue(up.consumed)
        XCTAssertEqual(up.reverseStyle, true, "the key-down style survives releasing Shift first")
        XCTAssertNil(state.handle(type: .keyUp, keyCode: 36, isRepeat: false, shiftHeld: false).reverseStyle)
        state.reset()
        XCTAssertNil(state.handle(type: .keyDown, keyCode: 36, isRepeat: true, shiftHeld: false).reverseStyle)
        XCTAssertNil(state.handle(type: .keyUp, keyCode: 36, isRepeat: false, shiftHeld: false).reverseStyle)
    }

    func testClipboardPanelSelectsNewestAndFiltersTextWithoutOpeningAWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let now = Date()
        let a = try store.add(.text(plain: "첫 번째 문장", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(-2))
        let b = try store.add(.image(data: Data([0x89, 0x50, 0x4E, 0x47]), type: .png), copiedAt: now.addingTimeInterval(-1))
        let c = try store.add(.text(plain: "Latest note", rtf: nil, html: nil), copiedAt: now)
        let panel = ClipboardHistoryPanelController()
        panel.updateEntries([a, c, b])
        XCTAssertEqual(panel.selectedEntry?.id, c.id)
        XCTAssertEqual(panel.visibleCount, 3)
        panel.search("첫 번째")
        XCTAssertEqual(panel.selectedEntry?.id, a.id)
        panel.search("없는 기록")
        XCTAssertNil(panel.selectedEntry)
        panel.search("")
        XCTAssertEqual(panel.selectedEntry?.id, c.id)
        let d = try store.add(.text(plain: "newest", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(1))
        panel.refreshPreservingSelection([a, b, c, d])
        XCTAssertEqual(panel.visibleCount, 4)
        XCTAssertEqual(panel.selectedEntry?.id, c.id, "new copies do not interrupt the current selection")
        panel.refreshAfterDeleting([c, a], previousRow: 1)
        XCTAssertEqual(panel.selectedEntry?.id, a.id)
        panel.refreshAfterDeleting([c], previousRow: 1)
        XCTAssertEqual(panel.selectedEntry?.id, c.id)
        XCTAssertFalse(panel.isVisible)
    }

    func testOversizedLatestCopyDoesNotOfferAnOlderItemForImmediatePaste() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-oversized-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let previous = try store.add(.text(plain: "previous item", rtf: nil, html: nil))
        let panel = ClipboardHistoryPanelController()
        panel.updateEntries([previous], latestCopyTooLarge: true)
        XCTAssertEqual(panel.visibleCount, 1)
        XCTAssertNil(panel.selectedEntry, "Enter must not paste an older item by accident")
        panel.refreshPreservingSelection([previous], latestCopyTooLarge: true)
        XCTAssertNil(panel.selectedEntry, "a late change notification must not select the older item")
        let root = try XCTUnwrap(panel.panel.contentView)
        let preview = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }
            .compactMap { $0.documentView as? NSTextView }.first)
        XCTAssertTrue(preview.string.contains("10 MiB"))
        root.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-clipboard-oversized-panel.png"))

        panel.search("previous")
        XCTAssertEqual(panel.selectedEntry?.id, previous.id)
        panel.refreshPreservingSelection([previous], latestCopyTooLarge: true)
        XCTAssertEqual(panel.selectedEntry?.id, previous.id, "an intentional selection remains stable")
        panel.search("")
        XCTAssertNil(panel.selectedEntry)
        panel.refreshPreservingSelection([previous])
        XCTAssertEqual(panel.selectedEntry?.id, previous.id)
    }

    func testLargeClipboardPreviewIsBoundedWhileSelectedContentStaysComplete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 300_000, maximumItemBytes: 200_000
        )
        let fullText = String(repeating: "한", count: 30_000)
        let entry = try store.add(.text(plain: fullText, rtf: nil, html: nil))
        let panel = ClipboardHistoryPanelController()
        panel.updateEntries([entry])
        let root = try XCTUnwrap(panel.panel.contentView)
        let preview = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }
            .compactMap { $0.documentView as? NSTextView }.first)
        let list = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }
            .compactMap { $0.documentView as? NSTableView }.first)
        let row = try XCTUnwrap(list.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(row.textField?.stringValue.count, 201)
        XCTAssertTrue(row.textField?.stringValue.hasSuffix("…") == true)
        XCTAssertEqual(preview.string.count, 20_002)
        XCTAssertTrue(preview.string.hasSuffix("\n…"))
        XCTAssertEqual(panel.selectedEntry?.content, .text(plain: fullText, rtf: nil, html: nil))
    }

    func testLargeClipboardSearchKeepsOnlyTheNewestQueryWithoutShowingAWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-search-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 3_000_000, maximumItemBytes: 1_500_000
        )
        let first = try store.add(.text(plain: String(repeating: "x", count: 600_000) + "needle", rtf: nil, html: nil))
        let second = try store.add(.text(plain: String(repeating: "y", count: 600_000) + "other", rtf: nil, html: nil))
        let panel = ClipboardHistoryPanelController()
        panel.updateEntries([first, second])

        panel.search("needle")
        XCTAssertNil(panel.selectedEntry, "an old row cannot be pasted while search is pending")
        panel.search("other")
        for _ in 0..<100 where panel.selectedEntry?.id != second.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(panel.selectedEntry?.id, second.id)
        let newer = try store.add(.text(plain: String(repeating: "z", count: 600_000) + "other", rtf: nil, html: nil))
        panel.refreshPreservingSelection([first, second, newer])
        XCTAssertNil(panel.selectedEntry)
        for _ in 0..<100 where panel.selectedEntry?.id != second.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(panel.selectedEntry?.id, second.id, "a new copy does not steal the selected result")
        panel.refreshAfterDeleting([first, newer], previousRow: 1)
        for _ in 0..<100 where panel.selectedEntry?.id != newer.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(panel.selectedEntry?.id, newer.id)
        panel.search("")
        XCTAssertEqual(panel.visibleCount, 2)
        XCTAssertEqual(panel.selectedEntry?.id, newer.id)
        panel.search("needle")
        XCTAssertNil(panel.selectedEntry)
        panel.close()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(panel.visibleCount, 0, "closing discards an in-flight search result")
        XCTAssertFalse(panel.isVisible)
    }

    func testIsolatedCopyFlowsThroughHistorySelectionAndTextImagePaste() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-flow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let copied = NSPasteboard.withUniqueName()
        let pasted = NSPasteboard.withUniqueName()
        defer { copied.releaseGlobally(); pasted.releaseGlobally() }
        let service = ClipboardCaptureService(store: store, pasteboard: copied) { _ in XCTFail("capture failed") }
        service.start()
        copied.clearContents()
        XCTAssertTrue(copied.setString("first", forType: .string))
        service.poll()
        copied.clearContents()
        XCTAssertTrue(copied.setString("second", forType: .string))
        service.poll()

        let panel = ClipboardHistoryPanelController()
        panel.updateEntries(try store.entries())
        XCTAssertEqual(panel.selectedEntry?.content, .text(plain: "second", rtf: nil, html: nil))
        panel.search("first")
        let selected = try XCTUnwrap(panel.selectedEntry)
        XCTAssertTrue(ClipboardPasteboardWriter.write(selected.content, style: .plain, to: pasted))
        XCTAssertEqual(pasted.string(forType: .string), "first")
        XCTAssertNil(ClipboardPasteboardReader.capture(from: pasted))

        let original = NSAttributedString(
            string: "Bold text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
        )
        let rtf = try original.data(
            from: NSRange(location: 0, length: original.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rich = NSPasteboardItem()
        XCTAssertTrue(rich.setString(original.string, forType: .string))
        XCTAssertTrue(rich.setData(rtf, forType: .rtf))
        copied.clearContents()
        XCTAssertTrue(copied.writeObjects([rich]))
        service.poll()

        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aJX8AAAAASUVORK5CYII="))
        let image = NSPasteboardItem()
        XCTAssertTrue(image.setData(png, forType: .png))
        copied.clearContents()
        XCTAssertTrue(copied.writeObjects([image]))
        service.poll()

        panel.search("")
        panel.updateEntries(try store.entries())
        let latestImage = try XCTUnwrap(panel.selectedEntry)
        XCTAssertEqual(latestImage.content, .image(data: png, type: .png))
        XCTAssertTrue(ClipboardPasteboardWriter.write(latestImage.content, style: .plain, to: pasted))
        let imageView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        XCTAssertTrue(imageView.readSelection(from: pasted, type: .png))
        XCTAssertNotNil(imageView.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)

        panel.search("Bold")
        let selectedRichText = try XCTUnwrap(panel.selectedEntry)
        XCTAssertTrue(ClipboardPasteboardWriter.write(selectedRichText.content, style: .formatted, to: pasted))
        let formattedView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        XCTAssertTrue(formattedView.readSelection(from: pasted, type: .rtf))
        XCTAssertEqual(formattedView.string, original.string)
        let pastedFont = try XCTUnwrap(formattedView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(pastedFont.fontDescriptor.symbolicTraits.contains(.bold))

        XCTAssertTrue(ClipboardPasteboardWriter.write(selectedRichText.content, style: .plain, to: pasted))
        let plainView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        XCTAssertTrue(plainView.readSelection(from: pasted, type: .string))
        XCTAssertEqual(plainView.string, original.string)
        let plainFont = plainView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(plainFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        service.stop()
    }

    func testRenderClipboardHistoryPanelWithoutShowingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-panel-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let thumbnailBitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        for x in 0..<16 {
            for y in 0..<16 {
                thumbnailBitmap.setColor(NSColor(deviceRed: 1, green: 0.4, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        XCTAssertGreaterThan(thumbnailBitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 0, 0)
        let png = try XCTUnwrap(thumbnailBitmap.representation(using: .png, properties: [:]))
        XCTAssertNotNil(NSImage(data: png))
        _ = try store.add(.image(data: png, type: .png))
        _ = try store.add(.text(plain: "첫 번째 기록\n여러 줄 텍스트", rtf: nil, html: nil))
        let panel = ClipboardHistoryPanelController()
        panel.updateEntries(try store.entries())
        let view = try XCTUnwrap(panel.panel.contentView)
        view.layoutSubtreeIfNeeded()
        let list = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }
            .compactMap { $0.documentView as? NSTableView }.first)
        let imageCell = try XCTUnwrap(list.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertNotNil(imageCell.imageView?.image)
        XCTAssertGreaterThan(imageCell.imageView?.frame.width ?? 0, 0)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-clipboard-panel.png"))
    }

    func testMousePermissionBlockIsBelowEveryMouseFeatureRow() throws {
        let controller = makeController()
        let wheel = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelSwitch,
            in: controller.view
        ))
        let side = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.sideSwitch,
            in: controller.view
        ))
        let wheelStep = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSwitch,
            in: controller.view
        ))
        let permissions = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.mousePermissions,
            in: controller.view
        ))

        let wheelFrame = wheel.convert(wheel.bounds, to: controller.view)
        let wheelStepFrame = wheelStep.convert(wheelStep.bounds, to: controller.view)
        let sideFrame = side.convert(side.bounds, to: controller.view)
        let permissionFrame = permissions.convert(permissions.bounds, to: controller.view)
        XCTAssertGreaterThan(wheelFrame.midY, sideFrame.midY)
        XCTAssertGreaterThan(wheelFrame.midY, wheelStepFrame.midY)
        XCTAssertGreaterThan(wheelStepFrame.midY, sideFrame.midY)
        XCTAssertGreaterThan(sideFrame.midY, permissionFrame.midY)
    }

    func testNativeGlassCardsOwnLaidOutProductionContentViews() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("NSGlassEffectView is available only on macOS 26 or later.")
        }
        let controller = SettingsViewController(renderingMode: .native)
        controller.view.frame = NSRect(origin: .zero, size: SettingsViewController.contentSize)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view is NSVisualEffectView)
        for identifier in [
            SettingsViewController.ControlIdentifier.keyboardGroup,
            SettingsViewController.ControlIdentifier.mouseGroup,
            SettingsViewController.ControlIdentifier.generalGroup
        ] {
            let glass = try XCTUnwrap(findView(identifier: identifier, in: controller.view) as? NSGlassEffectView)
            let content = try XCTUnwrap(glass.contentView)
            XCTAssertGreaterThan(glass.frame.width, 0)
            XCTAssertGreaterThan(glass.frame.height, 0)
            XCTAssertEqual(content.bounds.size, glass.bounds.size)
            XCTAssertFalse(content.subviews.isEmpty)
        }

        let permissionBlock = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.mousePermissions,
            in: controller.view
        ))
        XCTAssertGreaterThan(permissionBlock.frame.width, 0)
        XCTAssertGreaterThan(permissionBlock.frame.height, 0)
    }

    func testEverySwitchUsesTheExistingSingleSettingsHook() throws {
        let controller = makeController()
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }

        let identifiers = [
            SettingsViewController.ControlIdentifier.capsSwitch,
            SettingsViewController.ControlIdentifier.finderCutPasteSwitch,
            SettingsViewController.ControlIdentifier.wheelSwitch,
            SettingsViewController.ControlIdentifier.wheelStepSwitch,
            SettingsViewController.ControlIdentifier.sideSwitch,
            SettingsViewController.ControlIdentifier.loginSwitch
        ]
        for identifier in identifiers {
            let toggle = try XCTUnwrap(findView(identifier: identifier, in: controller.view) as? NSSwitch)
            toggle.performClick(nil)
        }

        XCTAssertEqual(received.count, 6)
        XCTAssertEqual(received.last, TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: true,
            fixedMouseWheelStepEnabled: true,
            finderCutPasteEnabled: true
        ))
    }

    func testClipboardFirstEnableRequiresARecordedShortcut() throws {
        let controller = makeController()
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }
        let toggle = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.clipboardHistorySwitch,
            in: controller.view
        ) as? NSSwitch)
        let options = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.clipboardOptions,
            in: controller.view
        ))
        XCTAssertTrue(options.isHidden)

        controller.captureClipboardShortcut = { nil }
        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(options.isHidden)
        XCTAssertTrue(received.isEmpty)

        let shortcut = TidyTapClipboardShortcut(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue)
        controller.captureClipboardShortcut = { shortcut }
        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off, "requested activation is not yet confirmed")
        XCTAssertTrue(options.isHidden)
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].clipboardHistoryEnabled)
        XCTAssertEqual(received[0].clipboardHistoryShortcut, shortcut)
        let requestID = UUID()
        controller.showApplyStatus(.pending(requestID))
        XCTAssertTrue(options.isHidden)

        controller.apply(.defaults)
        controller.showApplyStatus(.init(
            applyRequestID: requestID, outcome: .failed,
            failedComponent: .eventTap, errorCode: "eventTap.creationFailed"
        ))
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(options.isHidden)

        toggle.performClick(nil)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(options.isHidden)
        controller.apply(received[1])
        controller.showApplyStatus(.applied(UUID(), effectiveSettings: received[1]))
        XCTAssertEqual(toggle.state, .on)
        XCTAssertFalse(options.isHidden)

        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(options.isHidden)
    }

    func testClipboardDefaultPasteStyleCanBeChangedIndependently() throws {
        var settings = TidyTapSettings.defaults
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryShortcut = .init(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue)
        let controller = makeController(settings: settings)
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }
        let popup = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.clipboardPasteStyle,
            in: controller.view
        ) as? NSPopUpButton)
        popup.selectItem(at: 1)
        _ = popup.sendAction(popup.action, to: popup.target)
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].pasteFormattedTextByDefault)
        XCTAssertTrue(received[0].clipboardHistoryEnabled)
        controller.apply(received[0])
        XCTAssertEqual(popup.indexOfSelectedItem, 1)
    }

    func testClipboardShortcutChangeDisplaysOnlyTheAppliedKey() throws {
        var original = TidyTapSettings.defaults
        original.clipboardHistoryEnabled = true
        original.clipboardHistoryShortcut = .init(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue)
        let controller = makeController(settings: original)
        var requests = [TidyTapSettings]()
        controller.onSettingsChange = { requests.append($0) }
        controller.captureClipboardShortcut = {
            TidyTapClipboardShortcut(keyCode: 11, modifiers: CGEventFlags.maskAlternate.rawValue)
        }
        let button = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.clipboardShortcutButton,
            in: controller.view
        ) as? NSButton)
        XCTAssertEqual(button.title, "⌥C")

        button.performClick(nil)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].clipboardHistoryShortcut?.keyCode, 11)
        XCTAssertEqual(button.title, "⌥C", "the old key is still shown while registration is pending")

        controller.apply(original)
        XCTAssertEqual(button.title, "⌥C", "a rejected key change keeps the old label")
        button.performClick(nil)
        controller.apply(requests[1])
        XCTAssertEqual(button.title, "⌥B")
    }

    func testFinderCutPasteSwitchUsesLocalizedCopyAndPreservesState() throws {
        var settings = TidyTapSettings.defaults
        settings.finderCutPasteEnabled = true
        let controller = makeController(settings: settings)
        let toggle = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.finderCutPasteSwitch,
            in: controller.view
        ) as? NSSwitch)

        XCTAssertEqual(toggle.state, .on)
        XCTAssertEqual(toggle.accessibilityLabel(), "Use cut in Finder")

        let captions = allTextFields(in: controller.view).map(\.stringValue)
        XCTAssertTrue(captions.contains("Cut with ⌘X and move with ⌘V"))

        controller.showApplyStatus(.pending(UUID()))
        XCTAssertFalse(toggle.isEnabled)
        controller.apply(settings)
        XCTAssertEqual(toggle.state, .on)
    }

    func testSwitchKeepsNativeTrackingUntilSynchronousPendingCallbackCompletes() throws {
        let controller = makeController()
        let caps = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.capsSwitch,
            in: controller.view
        ) as? NSSwitch)
        var submitted = [TidyTapSettings]()
        controller.onSettingsChange = { settings in
            submitted.append(settings)
            controller.showApplyStatus(.pending(UUID()))
        }

        caps.performClick(nil)

        // The synchronous callback has requested pending state, but the
        // originating NSSwitch remains enabled through its tracking turn.
        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(caps.state, .on)
        XCTAssertTrue(caps.isEnabled)

        drainMainQueue()
        XCTAssertFalse(caps.isEnabled)
        XCTAssertEqual(caps.state, .on)

        controller.apply(submitted[0])
        controller.showApplyStatus(.init(
            applyRequestID: UUID(), outcome: .applied, failedComponent: nil, errorCode: nil
        ))
        XCTAssertTrue(caps.isEnabled)
        XCTAssertEqual(caps.state, .on)

        caps.performClick(nil)
        XCTAssertEqual(submitted.count, 2)
        XCTAssertEqual(caps.state, .off)
        drainMainQueue()
        XCTAssertFalse(caps.isEnabled)

        controller.apply(submitted[1])
        controller.showApplyStatus(.init(
            applyRequestID: UUID(), outcome: .applied, failedComponent: nil, errorCode: nil
        ))
        XCTAssertTrue(caps.isEnabled)
        XCTAssertEqual(caps.state, .off)
    }

    func testWheelStepSliderIsAlwaysVisibleAndRetainsItsValueWhileDisabled() throws {
        var settings = TidyTapSettings.defaults
        settings.mouseWheelStepLines = 7
        let controller = makeController(settings: settings)
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }

        let slider = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSlider,
            in: controller.view
        ) as? NSSlider)
        let value = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepValue,
            in: controller.view
        ) as? NSTextField)
        let toggle = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSwitch,
            in: controller.view
        ) as? NSSwitch)

        XCTAssertEqual(slider.integerValue, 7)
        XCTAssertEqual(value.stringValue, "7 lines")
        XCTAssertFalse(slider.isEnabled)

        toggle.performClick(nil)

        XCTAssertEqual(received, [TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: false,
            fixedMouseWheelStepEnabled: true,
            mouseWheelStepLines: 7
        )])
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.integerValue, 7)
    }

    func testWheelStepSliderCommitsDiscreteChangesAndRecoversFromPendingState() throws {
        var settings = TidyTapSettings.defaults
        settings.fixedMouseWheelStepEnabled = true
        let controller = makeController(settings: settings)
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }
        let slider = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSlider,
            in: controller.view
        ) as? NSSlider)

        slider.integerValue = 8
        _ = slider.sendAction(slider.action, to: slider.target)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].mouseWheelStepLines, 8)

        controller.showApplyStatus(.pending(UUID()))
        XCTAssertFalse(slider.isEnabled)

        var recovered = TidyTapSettings.defaults
        recovered.fixedMouseWheelStepEnabled = true
        recovered.mouseWheelStepLines = 3
        controller.apply(recovered)
        controller.showApplyStatus(TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .failed,
            failedComponent: .settings,
            errorCode: "settings.writeFailed",
            effectiveSettings: recovered
        ))

        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.integerValue, 3)
    }

    func testOnlyAccessibilityPermissionActionIsExposedAndNeverChangesSettings() throws {
        let controller = makeController()
        var permissions = [TidyTapPermission]()
        var settingChanges = [TidyTapSettings]()
        controller.onPermissionSettingsRequest = { permissions.append($0) }
        controller.onSettingsChange = { settingChanges.append($0) }

        let accessibilityRow = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.accessibilityPermission,
            in: controller.view
        ))
        let permissionCopy = allTextFields(in: try XCTUnwrap(
            findView(identifier: SettingsViewController.ControlIdentifier.mousePermissions, in: controller.view)
        )).map(\.stringValue)
        XCTAssertTrue(permissionCopy.contains("PERMISSIONS FOR INPUT FEATURES"))
        XCTAssertTrue(permissionCopy.contains("Required for mouse, Finder cut/paste, and clipboard history"))
        try XCTUnwrap(findButton(permission: .accessibility, in: accessibilityRow)).performClick(nil)

        XCTAssertNil(findView(identifier: "settings.permission.inputMonitoring", in: controller.view))
        XCTAssertNil(findButton(permission: .inputMonitoring, in: controller.view))
        XCTAssertEqual(permissions, [.accessibility])
        XCTAssertTrue(settingChanges.isEmpty)
        XCTAssertEqual(controller.settings, .defaults)
    }

    func testPermissionFailureUsesInputFeatureGuidance() throws {
        let controller = makeController()
        controller.showApplyStatus(
            .init(applyRequestID: UUID(), outcome: .failed, failedComponent: .settings,
                  errorCode: "settings.permissionDenied"),
            permission: .inputMonitoring
        )

        let status = try XCTUnwrap(findView(identifier: "settings.apply.status", in: controller.view) as? NSTextField)
        XCTAssertEqual(status.stringValue, "Review the input feature permission status below.")
    }

    func testKeyboardArrowsMoveExactlyOneLineAndPendingIgnoresInput() throws {
        var settings = TidyTapSettings.defaults
        settings.fixedMouseWheelStepEnabled = true
        let controller = makeController(settings: settings)
        let slider = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSlider,
            in: controller.view
        ) as? NSSlider)
        var received = [TidyTapSettings]()
        controller.onSettingsChange = { received.append($0) }
        let right = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{F703}",
            charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124
        ))
        slider.keyDown(with: right)
        XCTAssertEqual(received.map(\.mouseWheelStepLines), [4])
        controller.showApplyStatus(.pending(UUID()))
        slider.keyDown(with: right)
        XCTAssertEqual(received.count, 1)
        for identifier in [
            SettingsViewController.ControlIdentifier.capsSwitch,
            SettingsViewController.ControlIdentifier.wheelSwitch,
            SettingsViewController.ControlIdentifier.wheelStepSwitch,
            SettingsViewController.ControlIdentifier.sideSwitch,
            SettingsViewController.ControlIdentifier.loginSwitch
        ] {
            XCTAssertFalse(try XCTUnwrap(findView(identifier: identifier, in: controller.view) as? NSSwitch).isEnabled)
        }
    }

    func testShortViewportCanScrollToGeneralSettingsAndToggleKeepsHeight() throws {
        let controller = makeController()
        controller.view.setFrameSize(NSSize(width: 560, height: 480))
        controller.view.layoutSubtreeIfNeeded()
        let general = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.generalGroup,
            in: controller.view
        ))
        let scroll = try XCTUnwrap(general.enclosingScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        let height = document.frame.height
        XCTAssertGreaterThan(height, scroll.contentView.bounds.height)
        let toggle = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelStepSwitch,
            in: controller.view
        ) as? NSSwitch)
        toggle.performClick(nil)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(document.frame.height, height)
        general.scrollToVisible(general.bounds)
        let generalRect = general.convert(general.bounds, to: document)
        XCTAssertTrue(scroll.documentVisibleRect.contains(generalRect))
    }

    func testUnconfirmedPermissionsRemainUnknownAndDoNotEnableFeatures() {
        let controller = makeController()

        XCTAssertEqual(controller.permissionState, .init())
        XCTAssertEqual(controller.settings, .defaults)

        controller.applyPermissionState(.init(accessibility: .authorized, inputMonitoring: .authorized))

        XCTAssertEqual(controller.settings, .defaults)
    }

    func testRenderOfflineSnapshots() throws {
        let outputDirectory = ProcessInfo.processInfo.environment["TIDYTAP_SETTINGS_SNAPSHOT_DIR"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("TidyTapSettingsSnapshots")

        for fixture in SettingsSnapshotRenderer.fixtures {
            let outputURL = outputDirectory.appendingPathComponent(fixture.filename)
            try SettingsSnapshotRenderer.render(fixture, to: outputURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testCapsLockFailureDisplaysLocalizedReasonAndPreservesEffectiveSettings() throws {
        for language in ["ko", "en"] {
            let resources = Bundle(for: Self.self)
            let path = try XCTUnwrap(resources.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let controller = SettingsViewController(localizationBundle: bundle)
            _ = controller.view
            var effective = TidyTapSettings.defaults
            effective.sideButtonNavigation = true
            controller.apply(effective)
            let status = TidyTapApplyStatus(
                applyRequestID: UUID(), outcome: .failed, failedComponent: .capsLock,
                errorCode: "capsLock.invalidSystemData.hidMappings", effectiveSettings: effective
            )
            controller.showApplyStatus(status)
            let label = try XCTUnwrap(findView(identifier: "settings.apply.status", in: controller.view) as? NSTextField)
            XCTAssertEqual(label.stringValue, language == "ko"
                ? "TidyTap이 현재 Caps Lock 키보드 설정을 읽을 수 없습니다."
                : "TidyTap could not read the current Caps Lock keyboard settings.")
            XCTAssertFalse(label.isHidden)
            XCTAssertEqual(controller.settings, effective)
            let caps = try XCTUnwrap(findView(identifier: SettingsViewController.ControlIdentifier.capsSwitch, in: controller.view) as? NSSwitch)
            XCTAssertEqual(caps.state, .off)
            XCTAssertTrue(caps.isEnabled)
        }
    }

    func testCapsLockRecoveryAndUnknownErrorKeepDistinctStatusMessages() throws {
        let controller = makeController()
        let label = try XCTUnwrap(findView(identifier: "settings.apply.status", in: controller.view) as? NSTextField)
        let recovery = TidyTapApplyStatus(applyRequestID: UUID(), outcome: .recoveryRequired,
            failedComponent: .capsLock, errorCode: "capsLock.recoveryRequired.hidMappings")
        controller.showApplyStatus(recovery)
        XCTAssertEqual(label.stringValue, TidyTapStrings.capsLockApplyMessage(for: recovery))
        controller.showApplyStatus(.init(applyRequestID: UUID(), outcome: .failed,
            failedComponent: .capsLock, errorCode: "capsLock.commandFailed"))
        XCTAssertEqual(label.stringValue, TidyTapStrings.changesCouldNotBeApplied)
        controller.showApplyStatus(.init(applyRequestID: UUID(), outcome: .pending, failedComponent: nil, errorCode: nil))
        XCTAssertEqual(label.stringValue, TidyTapStrings.applyingChanges)
        let caps = try XCTUnwrap(findView(identifier: SettingsViewController.ControlIdentifier.capsSwitch, in: controller.view) as? NSSwitch)
        XCTAssertFalse(caps.isEnabled)
    }

    func testClipboardReadDenialExplainsWhyHistoryWasDisabled() throws {
        let controller = makeController()
        let label = try XCTUnwrap(findView(identifier: "settings.apply.status", in: controller.view) as? NSTextField)
        controller.showApplyStatus(.init(
            applyRequestID: UUID(), outcome: .failed,
            failedComponent: .eventTap, errorCode: "clipboardHistory.readDenied"
        ))
        XCTAssertEqual(label.stringValue, String(
            localized: "Clipboard access is denied. Allow TidyTap to read the clipboard, then turn history on again.",
            bundle: .main
        ))
        XCTAssertFalse(label.isHidden)
    }

    func testEventTapFailureWithCapsLockRollbackDisplaysRestoreMessage() throws {
        for language in ["ko", "en"] {
            let resources = Bundle(for: Self.self)
            let path = try XCTUnwrap(resources.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let controller = SettingsViewController(localizationBundle: bundle)
            _ = controller.view
            let label = try XCTUnwrap(findView(identifier: "settings.apply.status", in: controller.view) as? NSTextField)
            let status = TidyTapApplyStatus(
                applyRequestID: UUID(),
                outcome: .recoveryRequired,
                failedComponent: .eventTap,
                errorCode: "lifecycle.rollbackFailed.capsLock"
            )

            controller.showApplyStatus(status)

            XCTAssertEqual(label.stringValue, language == "ko"
                ? "계속하기 전에 Caps Lock 변경 사항을 복원해야 합니다."
                : "Caps Lock changes need to be restored before you continue.")
        }
    }

    private func makeController(settings: TidyTapSettings = .defaults) -> SettingsViewController {
        let controller = SettingsViewController(settings: settings)
        controller.view.frame = NSRect(origin: .zero, size: SettingsViewController.contentSize)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let match = findView(identifier: identifier, in: child) {
                return match
            }
        }
        return nil
    }

    private func findButton(permission: TidyTapPermission, in root: NSView) -> NSButton? {
        if let button = root as? NSButton,
           button.identifier?.rawValue == permission.rawValue {
            return button
        }
        for child in root.subviews {
            if let match = findButton(permission: permission, in: child) {
                return match
            }
        }
        return nil
    }

    private func allTextFields(in root: NSView) -> [NSTextField] {
        let own = (root as? NSTextField).map { [$0] } ?? []
        return own + root.subviews.flatMap { allTextFields(in: $0) }
    }

    private func drainMainQueue() {
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
    }
}
