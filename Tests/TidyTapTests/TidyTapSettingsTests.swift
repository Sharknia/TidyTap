import XCTest

final class TidyTapSettingsTests: XCTestCase {
    func testDefaultSettingsKeepEveryCapabilityDisabled() {
        XCTAssertEqual(TidyTapSettings.defaults, TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: false,
            showInMenuBar: false
        ))
    }

    func testBundleIdentifiersUseTheTidyTapNamespace() {
        XCTAssertEqual(TidyTapProduct.appBundleIdentifier, "com.sharknia.TidyTap")
        XCTAssertEqual(TidyTapProduct.helperBundleIdentifier, "com.sharknia.TidyTap.Helper")
    }
}
