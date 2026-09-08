# Development and validation notes

[Back to the user guide](../README.md)

## Build and test

Use an Apple silicon Mac and a full Xcode installation with Swift 6 support. The app targets macOS 15.1 or later. Run commands from the repository root. The documentation checks used Xcode 26.6; this is not a minimum-version claim.

List targets and schemes:

```sh
xcodebuild -project TidyTap.xcodeproj -list
```

Build without signing credentials:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
```

Run the app tests and the Swift package tests:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
swift test --package-path Packages/TidyTapInputEngine
```

Run the process-level launch smoke after changing either app entry point:

```sh
Scripts/launch-smoke.sh
```

It builds an unsigned Release app, applies an ad-hoc signature, launches the
main app and helper with isolated all-off preferences, verifies one settings
window plus helper startup/exit, and checks that live input and production
preference state did not change.

To create a signed archive, copy `Config/LocalSigning.xcconfig.example` to the gitignored `Config/LocalSigning.xcconfig` and provide a real Developer ID identity. Do not commit signing values.

## Recorded validation scope


- Checked: Apple M3 Pro MacBook Pro on macOS 26.5.2, release 0.1.3 launch smoke and system-state preservation.
- Remaining live checks: macOS 15.1 runtime, Caps Lock backup/restoration, permission changes, integrated wheel/navigation behavior, login/helper lifetime, and removal.
- Finder-specific results are in [Finder validation](FINDER_CUT_PASTE_VALIDATION.md).

Project version: `0.1.3`. Published versions and signed downloads are listed on [GitHub Releases](https://github.com/Sharknia/TidyTap/releases).

See the [MVP work plan](MVP_PLAN.md) and [Korean README](../README.ko.md).

## Implementation details


- Use Caps Lock as a two-input-source switch (mapped to F18), without toggling Caps Lock.
- Reverse vertical scrolling for any non-continuous, line-based mouse-wheel event while leaving trackpad scrolling unchanged. The implementation does not filter by vendor.
- Independently enable a fixed wheel step size (1-10 logical lines, default 3). It starts off and remembers the chosen size while disabled. Single-step non-continuous events are adjusted; larger deltas retain their original magnitude. This is not a claim of complete acceleration removal for every wheel or scrolling speed. Physical validation of this new feature remains separate.
- Use mouse buttons 3/4 for back/forward in the active Safari or Finder window.
- Cut files in Finder with `⌘X` and move them with `⌘V`; ordinary `⌘C → ⌘V` still copies. TidyTap briefly shows “Move ready” or “Copy ready” beside the selected item for about one second. This feature starts off and preserves normal text editing in rename and search fields.

Each feature has its own toggle. The settings window also offers **Start at login**. Grant Accessibility to **TidyTap** for mouse features; the worker is an executable inside the same app bundle, not a separate permission target. TidyTap remains a normal Dock app, and quitting it with `Command-Q` does not stop an enabled helper.

Finder cut/paste is included in the 0.1.3 release. Its move intent is cleared when the move command is sent, so cancelling or failing the Finder operation requires cutting again. Desktop, other file managers, and context-menu paste are not remapped. See the [design](FINDER_CUT_PASTE_PLAN.md) and [validation scope](FINDER_CUT_PASTE_VALIDATION.md).


[Architecture](ARCHITECTURE.md) · [Permissions](PERMISSION_OWNERSHIP.md) · [Release workflow](RELEASE.md) · [Wheel step validation](WHEEL_STEP_SIZE_VALIDATION.md)
