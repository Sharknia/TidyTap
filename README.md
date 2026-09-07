# TidyTap

[![Release](https://img.shields.io/github/v/release/Sharknia/TidyTap?include_prereleases&label=release)](https://github.com/Sharknia/TidyTap/releases)
[![Asset downloads](https://img.shields.io/github/downloads/Sharknia/TidyTap/total?label=asset%20downloads)](https://github.com/Sharknia/TidyTap/releases)
[![Languages](https://img.shields.io/badge/languages-%ED%95%9C%EA%B5%AD%EC%96%B4%20%2F%20English-2ea44f)](README.ko.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)

TidyTap is a small macOS input utility:

- Use Caps Lock as a two-input-source switch (mapped to F18), without toggling Caps Lock.
- Reverse vertical scrolling for any non-continuous, line-based mouse-wheel event while leaving trackpad scrolling unchanged. The supported target remains the VXE Mouse 1K Dongle; prior physical validation covers device classification and button reports, not the new fixed-step behavior. The implementation does not filter by vendor.
- Independently enable a fixed wheel step size (1–10 logical lines, default 3). It starts off and remembers the chosen size while disabled. Single-step non-continuous events are adjusted; larger deltas retain their original magnitude. This is not a claim of complete acceleration removal for every wheel or scrolling speed. Physical validation of this new feature remains separate.
- Use mouse buttons 3/4 for back/forward in the active Safari or Finder window.
- Cut files in Finder with `⌘X` and move them with `⌘V`; ordinary `⌘C → ⌘V` still copies. TidyTap briefly shows “Move ready” or “Copy ready” beside the selected item for about one second. This feature starts off and preserves normal text editing in rename and search fields.

Each feature has its own toggle. The settings window also offers **Start at login**. Grant Accessibility to **TidyTap** for mouse features; the worker is an executable inside the same app bundle, not a separate permission target. TidyTap remains a normal Dock app, and quitting it with `Command-Q` does not stop an enabled helper.

Finder cut/paste is included in the 0.1.3 release. Its move intent is cleared when the move command is sent, so cancelling or failing the Finder operation requires cutting again. Desktop, other file managers, and context-menu paste are not remapped. See the [design](docs/FINDER_CUT_PASTE_PLAN.md) and [validation scope](docs/FINDER_CUT_PASTE_VALIDATION.md).

## Support and status

TidyTap supports Apple silicon Macs running macOS 15.1 (Sequoia) or later. This 15.1-targeted build was checked on MacBook Pro `Mac15,6` (Apple M3 Pro) and macOS 26.5.2 (`25F84`); macOS 15.1 runtime validation remains outstanding. The 0.1.3 release launch-smoke, including its final system-state preservation check, passed. Physical validation covers scroll-device classification (VXE versus the built-in and Magic Trackpad) and that the VXE side buttons report as Core Graphics buttons 3/4. Remaining integrated live validation includes Caps Lock/input-source backup and restore, permission grant/revocation behavior, end-to-end wheel and Safari/Finder navigation, helper lifetime/login behavior, and the supported removal sequence; these are not claimed complete. The UI is available in English and Korean.

Project version: `0.1.3`. Published versions and signed downloads are listed on [GitHub Releases](https://github.com/Sharknia/TidyTap/releases).

See the [MVP work plan](docs/MVP_PLAN.md) and [Korean README](README.ko.md).

## Permissions

If you already remapped the Caps Lock position to another key such as F19 using VIA and configured your input-source shortcut accordingly, leave TidyTap's Caps Lock feature off. This feature maps actual Caps Lock input to F18 and changes the macOS input-source shortcut to F18. It does not detect or reuse a custom binding. Mouse features remain independent.

- Caps Lock input-source switching: no Accessibility or Input Monitoring permission.
- Mouse wheel reversal and fixed step size: Accessibility.
- Safari/Finder side-button navigation: Accessibility only.

Accessibility also permits event listening, so you do not need to add TidyTap separately to Input Monitoring. The worker still checks actual event access and event-tap creation. Missing Accessibility is reported as a permission requirement; failure to start input processing despite access is reported as an apply failure. The permission button asks the embedded helper (the process that uses the permission) through the public macOS API; returning to TidyTap refreshes the helper's current status without turning a disabled feature back on. Side-button events pass through in unsupported apps; continuous or otherwise unknown scrolling also passes through.

## Install and run

Download release DMGs from [GitHub Releases](https://github.com/Sharknia/TidyTap/releases). For development, build the app locally, then open the resulting app:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
```

The app opens as a normal Dock application with one settings window. Enabling an input feature launches the embedded background-only `TidyTapHelper`; settings changes are applied from the saved snapshot. **Start at login** registers the helper for the next login. Turning it off removes automatic startup; enabled features continue in the manually launched worker. When all input features are off, including fixed wheel step size, the helper removes its event tap and exits after restoring owned state.

## Removing TidyTap / restoring state

Use this order so Caps Lock backups and the helper are safely restored:

1. Turn off all input features and **Start at login**.
2. Confirm that the Caps Lock backup has been restored and the helper has exited.
3. Quit TidyTap and delete `TidyTap.app`.

Deleting the app first is not supported for automatic restoration. TidyTap does not remove third-party utilities. Stop or disable conflicting tools such as Scroll Reverser or a personal Caps Lock LaunchAgent yourself before validation.

## Development

List targets and schemes:

```sh
xcodebuild -project TidyTap.xcodeproj -list
```

Build without signing credentials:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
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

## Privacy and limitations

TidyTap makes no network requests and has no telemetry, analytics, cloud sync, updater, or key/mouse recording. Event callbacks process only the required button and scroll values in memory; they are not stored.

The MVP does not provide custom mappings, profiles, horizontal-scroll reversal, speed/acceleration controls, navigation outside Safari/Finder, inactive-window navigation, a menu-bar item, an uninstaller, or automatic helper restart. Input-source list management is also out of scope. The supported removal sequence above is required.

## Contact

- Email: [zel@kakao.com](mailto:zel@kakao.com)
- GitHub: [Sharknia/TidyTap](https://github.com/Sharknia/TidyTap)

## License

TidyTap is released under the [MIT License](LICENSE).
