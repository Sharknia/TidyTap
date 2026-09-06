#!/bin/zsh
# Verify the exact DMG produced by package-release-dmg.sh before publication.
set -euo pipefail

if (( $# != 2 )); then
  print -u2 -- "Usage: ${0:t} path/to/TidyTap-<version>.dmg <version>"
  exit 2
fi

dmg_path="${1:A}"
expected_version="$2"
project_root="${0:A:h:h}"

if [[ ! "$expected_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 -- "Expected version must match MAJOR.MINOR.PATCH."
  exit 2
fi
if [[ ! -f "$dmg_path" ]]; then
  print -u2 -- "Missing DMG: $dmg_path"
  exit 1
fi

dmg_name="TidyTap-$expected_version.dmg"
if [[ "${dmg_path:t}" != "$dmg_name" ]]; then
  print -u2 -- "DMG filename does not match version $expected_version."
  exit 1
fi

"$project_root/Scripts/verify-dmg-sidecar.sh" "$dmg_path"

mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/tidytap-release-mount.XXXXXX")
device=""
cleanup() {
  if [[ -n "$device" ]]; then
    /usr/bin/hdiutil detach "$device" -force >/dev/null 2>&1 || true
  fi
  rmdir "$mount_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

device=$(/usr/bin/hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$mount_dir" | /usr/bin/awk 'NR == 1 { print $1 }')
app_path="$mount_dir/TidyTap.app"
if [[ ! -d "$app_path" ]]; then
  print -u2 -- "DMG does not contain a top-level TidyTap.app."
  exit 1
fi
applications_target=$(/usr/bin/readlink "$mount_dir/Applications" 2>/dev/null || true)
if [[ ! -L "$mount_dir/Applications" || "$applications_target" != "/Applications" ]]; then
  print -u2 -- "DMG does not contain the /Applications install link."
  exit 1
fi
visible_items=("$mount_dir"/*(N))
if (( ${#visible_items} != 2 )) || \
  [[ "${visible_items[1]:t}" != "Applications" || "${visible_items[2]:t}" != "TidyTap.app" ]]; then
  print -u2 -- "DMG must expose only Applications and TidyTap.app."
  exit 1
fi

helper_path="$app_path/Contents/MacOS/TidyTapHelper"
if [[ ! -f "$helper_path" || ! -x "$helper_path" ]]; then
  print -u2 -- "DMG app does not contain an executable plain TidyTapHelper."
  exit 1
fi
if /usr/bin/find "$app_path/Contents" -type d -name '*.app' -print -quit | /usr/bin/grep -q .; then
  print -u2 -- "DMG app contains an unexpected nested app bundle."
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ "$version" != "$expected_version" ]]; then
  print -u2 -- "DMG app version $version does not match $expected_version."
  exit 1
fi

agent_plist="$app_path/Contents/Library/LaunchAgents/com.sharknia.TidyTap.Agent.plist"
if [[ ! -f "$agent_plist" ]]; then
  print -u2 -- "DMG app is missing its LaunchAgent plist."
  exit 1
fi
bundle_program=$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$agent_plist")
if [[ "$bundle_program" != "Contents/MacOS/TidyTapHelper" ]]; then
  print -u2 -- "LaunchAgent does not target the embedded plain helper."
  exit 1
fi

print -- "Release artifact contents verified: $dmg_name"
