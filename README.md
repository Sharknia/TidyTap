# TidyTap

[![Release](https://img.shields.io/github/v/release/Sharknia/TidyTap?include_prereleases&label=release)](https://github.com/Sharknia/TidyTap/releases)
[![Asset downloads](https://img.shields.io/github/downloads/Sharknia/TidyTap/total?label=asset%20downloads)](https://github.com/Sharknia/TidyTap/releases)
[![Languages](https://img.shields.io/badge/languages-%ED%95%9C%EA%B5%AD%EC%96%B4%20%2F%20English-2ea44f)](README.ko.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)

TidyTap is a small macOS utility for three input annoyances:

- Use Caps Lock as a two-input-source switch (mapped to F18), without toggling Caps Lock.
- Reverse vertical scrolling for any non-continuous, line-based mouse-wheel event while leaving trackpad scrolling unchanged. Only the VXE Mouse 1K Dongle is physically verified and supported for `0.1.0`; the implementation does not filter by vendor.
- Use mouse buttons 3/4 for back/forward in the active Safari or Finder window.

Each feature has its own toggle. The settings window also offers **Start at login**. Accessibility and Input Monitoring are granted to **TidyTap**; the worker is an executable inside the same app bundle, not a separate permission target. TidyTap remains a normal Dock app, and quitting it with `Command-Q` does not stop an enabled helper.

## Support and status

The development build is being checked on MacBook Pro `Mac15,6` (Apple M3 Pro) and macOS 26.6.2 (`25G83`). Physical validation so far covers scroll-device classification (VXE versus the built-in and Magic Trackpad) and that the VXE side buttons report as Core Graphics buttons 3/4. Remaining integrated live validation includes Caps Lock/input-source backup and restore, permission grant/revocation behavior, end-to-end wheel and Safari/Finder navigation, helper lifetime/login behavior, and the supported removal sequence; these are not claimed complete. The UI is available in English and Korean. Other Macs or macOS versions may run, but are not compatibility claims for `0.1.0`.

Status: `0.1.0` release. A notarized `v0.1.0` release is available.

See the [MVP work plan](docs/MVP_PLAN.md) and [Korean README](README.ko.md).

## Permissions

- Caps Lock input-source switching: no Accessibility or Input Monitoring permission.
- Mouse wheel reversal: Accessibility **and** Input Monitoring.
- Safari/Finder side-button navigation: Accessibility only.

If a required permission is missing or later revoked, the affected feature is not applied and the settings window names Accessibility or Input Monitoring explicitly. Its permission button asks the embedded helper (the process that uses the permission) through the public macOS API; returning to TidyTap refreshes the helper's current status without turning a disabled feature back on. Side-button events pass through in unsupported apps; continuous or otherwise unknown scrolling also passes through.

## Install and run

A notarized [`v0.1.0` release](https://github.com/Sharknia/TidyTap/releases/tag/v0.1.0) is available. For development, build the app locally, then open the resulting app:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
```

The app opens as a normal Dock application with one settings window. Enabling a core feature launches the embedded background-only `TidyTapHelper`; settings changes are applied from the saved snapshot. **Start at login** registers the helper for the next login. Turning it off removes automatic startup; enabled features continue in the manually launched worker. When all three features are off, the helper removes its event tap and exits after restoring owned state.

## Removing TidyTap / restoring state

Use this order so Caps Lock backups and the helper are safely restored:

1. Turn off all three features and **Start at login**.
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
