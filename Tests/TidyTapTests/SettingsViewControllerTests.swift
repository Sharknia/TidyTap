import AppKit
import XCTest

@MainActor
final class SettingsViewControllerTests: XCTestCase {
    func testMousePermissionBlockIsBelowBothMouseFeatureRows() throws {
        let controller = makeController()
        let wheel = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.wheelSwitch,
            in: controller.view
        ))
        let side = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.sideSwitch,
            in: controller.view
        ))
        let permissions = try XCTUnwrap(findView(
            identifier: SettingsViewController.ControlIdentifier.mousePermissions,
            in: controller.view
        ))

        let wheelFrame = wheel.convert(wheel.bounds, to: controller.view)
        let sideFrame = side.convert(side.bounds, to: controller.view)
        let permissionFrame = permissions.convert(permissions.bounds, to: controller.view)
        XCTAssertGreaterThan(wheelFrame.midY, sideFrame.midY)
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
            SettingsViewController.ControlIdentifier.sideSwitch,
            SettingsViewController.ControlIdentifier.loginSwitch
        ]
        for identifier in identifiers {
            let toggle = try XCTUnwrap(findView(identifier: identifier, in: controller.view) as? NSSwitch)
            toggle.performClick(nil)
        }

        XCTAssertEqual(received.count, 4)
        XCTAssertEqual(received.last, TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: true
        ))
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

    private func makeController() -> SettingsViewController {
        let controller = SettingsViewController()
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
