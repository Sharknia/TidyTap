# TidyTap

TidyTap is a lightweight macOS utility for a tidier keyboard and mouse experience.

Planned features:

- Use Caps Lock exclusively to switch input sources.
- Reverse vertical scrolling for a mouse without changing trackpad scrolling.
- Enable mouse side-button navigation in Safari and Finder.
- Toggle each feature independently.
- Launch at login and optionally show a menu bar item.

TidyTap will use a regular Dock app for configuration and a lightweight background helper so mouse features can continue after the configuration app quits.

## Status

Initial development.

The scope for `0.1.0` is frozen in the [MVP work plan](docs/MVP_PLAN.md).

## Local signing and release builds

Debug builds and tests intentionally work without signing credentials. Release
targets enable the Hardened Runtime, but unsigned Release builds and archives
remain available with `CODE_SIGNING_ALLOWED=NO`.

To produce a signed distribution archive, copy
`Config/LocalSigning.xcconfig.example` to the gitignored
`Config/LocalSigning.xcconfig`, then supply the real Apple Developer team ID
and `Developer ID Application` identity. The same settings are consumed by
both `TidyTap` and its embedded `TidyTapHelper`; do not commit those values.

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Release \
  -archivePath /tmp/TidyTap.xcarchive archive
```

Notarization and a distributable `0.1.0` release are blocked until valid
Developer ID signing and notarization credentials are supplied.

## Contact

- Email: zel@kakao.com
- GitHub: [Sharknia](https://github.com/Sharknia)
