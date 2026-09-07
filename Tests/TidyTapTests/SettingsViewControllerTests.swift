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
            SettingsViewController.ControlIdentifier.wheelSwitch,
            SettingsViewController.ControlIdentifier.wheelStepSwitch,
            SettingsViewController.ControlIdentifier.sideSwitch,
            SettingsViewController.ControlIdentifier.loginSwitch
        ]
        for identifier in identifiers {
            let toggle = try XCTUnwrap(findView(identifier: identifier, in: controller.view) as? NSSwitch)
            toggle.performClick(nil)
        }

        XCTAssertEqual(received.count, 5)
        XCTAssertEqual(received.last, TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: true,
            fixedMouseWheelStepEnabled: true
        ))
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

    func testPermissionActionsRouteTheirExactPermissionAndNeverChangeSettings() throws {
        let controller = makeController()
        var permissions = [TidyTapPermission]()
        var settingChanges = [TidyTapSettings]()
        controller.onPermissionSettingsRequest = { permissions.append($0) }
        controller.onSettingsChange = { settingChanges.append($0) }

        let accessibilityRow = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.accessibilityPermission,
            in: controller.view
        ))
        let inputMonitoringRow = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.inputMonitoringPermission,
            in: controller.view
        ))
        try XCTUnwrap(findButton(permission: .accessibility, in: accessibilityRow)).performClick(nil)
        try XCTUnwrap(findButton(permission: .inputMonitoring, in: inputMonitoringRow)).performClick(nil)

        XCTAssertEqual(permissions, [.accessibility, .inputMonitoring])
        XCTAssertTrue(settingChanges.isEmpty)
        XCTAssertEqual(controller.settings, .defaults)
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
}
