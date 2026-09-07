import AppKit
import XCTest

@MainActor
final class SettingsViewControllerTests: XCTestCase {
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
        XCTAssertTrue(permissionCopy.contains("Required for mouse features and Finder cut/paste"))
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
