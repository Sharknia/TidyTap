#!/bin/zsh
# Build a local, unsigned preview DMG. This is deliberately not a release
# artifact: it has no Developer ID signature and is not submitted to Apple.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

configuration="Release"
derived_data="$project_root/build/preview-derived-data"
output_dir="$project_root/build/artifacts"
volume_name="TidyTap Preview"

rm -rf "$derived_data"
mkdir -p "$output_dir"

xcodebuild \
  -quiet \
  -project TidyTap.xcodeproj \
  -scheme TidyTap \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

app_path="$derived_data/Build/Products/$configuration/TidyTap.app"
helper_path="$app_path/Contents/Library/LoginItems/TidyTapHelper.app"

if [[ ! -d "$app_path" || ! -d "$helper_path" ]]; then
  print -u2 -- "Build did not produce TidyTap.app with its embedded TidyTapHelper.app."
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ -z "$version" ]]; then
  print -u2 -- "Could not determine the app version."
  exit 1
fi

dmg_path="$output_dir/TidyTap-$version-preview-unsigned.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/TidyTap-preview.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT

/usr/bin/ditto "$app_path" "$staging_dir/TidyTap.app"
/usr/bin/hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
print -- "Created unsigned preview DMG: $dmg_path"
print -- "SHA-256: $(cut -d ' ' -f 1 "$dmg_path.sha256")"
