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

- The 0.1.4 release merge passed 115 app tests and 101 input-engine tests. Its macOS 26.6.2 VM check covered first permission approval, four input-feature switches, settings retention, and helper shutdown with all features off. See the [0.1.4 release notes](RELEASE_NOTES_0.1.4.md).
- Earlier physical-Mac checks used an Apple M3 Pro MacBook Pro on macOS 26.5.2. Finder-specific results are in [Finder validation](FINDER_CUT_PASTE_VALIDATION.md).
- Remaining live checks include macOS 15.1 runtime, physical Caps Lock and mouse coverage, permission changes, login/helper lifetime, and removal. Clipboard history has [separate acceptance status](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md); passing its code tests does not complete these live checks.

Project version: `0.2.3` (build 9). Published versions and signed downloads are listed on [GitHub Releases](https://github.com/Sharknia/TidyTap/releases).

See the [MVP work plan](MVP_PLAN.md) and [Korean README](../README.ko.md).

## Implementation details


- Use Caps Lock as a two-input-source switch (mapped to F18), without toggling Caps Lock.
- Reverse vertical scrolling for any non-continuous, line-based mouse-wheel event while leaving trackpad scrolling unchanged. The implementation does not filter by vendor.
- Independently enable a fixed wheel step size (1-10 logical lines, default 3). It starts off and remembers the chosen size while disabled. Single-step non-continuous events are adjusted; larger deltas retain their original magnitude. This is not a claim of complete acceleration removal for every wheel or scrolling speed. Physical validation of this new feature remains separate.
- Use mouse buttons 3/4 for back/forward in the active Safari or Finder window.
- Cut files in Finder with `⌘X` and move them with `⌘V`; ordinary `⌘C → ⌘V` still copies. TidyTap briefly shows “Move ready” or “Copy ready” beside the selected item for about one second. This feature starts off and preserves normal text editing in rename and search fields.

Each feature has its own toggle. The settings window also offers **Start at login**. Grant Accessibility to **TidyTap** for mouse features; the worker is an executable inside the same app bundle, not a separate permission target. TidyTap remains a normal Dock app, and quitting it with `Command-Q` does not stop an enabled helper.

Version 0.2.0 adds opt-in clipboard history and Sparkle updates. Clipboard capture runs in the existing helper; the app opens a single search/preview panel and sends a selected entry ID back to the helper for paste. It retains supported copied text and images locally for 7 days, up to 100 entries, 50 MiB total, and 10 MiB per entry; identical recopy or a successful paste request moves one entry to the top and renews retention. Clipboard read status is distinct from Accessibility. [Requirements](CLIPBOARD_HISTORY_URS.md), [work plan](CLIPBOARD_HISTORY_WORK_PLAN.md), and [acceptance status](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md) record what is implemented and what still needs live validation. For the signed DMG and update feed workflow, see [Release workflow](RELEASE.md).

Finder cut/paste is included in the 0.1.3 release. Its move intent is cleared when the move command is sent, so cancelling or failing the Finder operation requires cutting again. Desktop, other file managers, and context-menu paste are not remapped. See the [design](FINDER_CUT_PASTE_PLAN.md) and [validation scope](FINDER_CUT_PASTE_VALIDATION.md).


[Architecture](ARCHITECTURE.md) · [Permissions](PERMISSION_OWNERSHIP.md) · [Release workflow](RELEASE.md) · [Wheel step validation](WHEEL_STEP_SIZE_VALIDATION.md)
