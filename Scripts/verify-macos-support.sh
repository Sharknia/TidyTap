#!/bin/zsh
# Check the app bundle's declared and linked minimum macOS version.
set -euo pipefail

if (( $# != 1 )); then
  print -u2 -- "Usage: ${0:t} path/to/TidyTap.app"
  exit 2
fi

app_path="${1:A}"
expected_version="15.1"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
  print -u2 -- "Missing TidyTap app bundle: $app_path"
  exit 1
fi

declared_version=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")
if [[ "$declared_version" != "$expected_version" ]]; then
  print -u2 -- "Info.plist minimum macOS version is $declared_version, expected $expected_version."
  exit 1
fi

for executable_name in TidyTap TidyTapHelper; do
  executable_path="$app_path/Contents/MacOS/$executable_name"
  if [[ ! -x "$executable_path" ]]; then
    print -u2 -- "Missing executable: $executable_path"
    exit 1
  fi

  architectures=$(lipo -archs "$executable_path")
  if [[ "$architectures" != "arm64" ]]; then
    print -u2 -- "$executable_name architectures are '$architectures', expected arm64."
    exit 1
  fi

  if ! xcrun vtool -show-build "$executable_path" | grep -Eq "^[[:space:]]*minos[[:space:]]+$expected_version$"; then
    print -u2 -- "$executable_name Mach-O minimum macOS version is not $expected_version."
    exit 1
  fi
done

print -- "macOS support metadata verified: arm64 app and helper require macOS $expected_version or later."
