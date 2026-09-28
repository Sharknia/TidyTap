#!/bin/zsh
# Prepare a Sparkle appcast with a signed DMG entry. Publishing
# the DMG and then this feed is a separate, explicit release operation.
set -euo pipefail

if (( $# != 2 )); then
  print -u2 -- "Usage: ${0:t} /path/to/TidyTap-<version>.dmg v<version>"
  exit 2
fi

project_root="${0:A:h:h}"
release_dmg="${1:A}"
tag="$2"
if [[ ! "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' || \
      ! -f "$release_dmg" || \
      "${release_dmg:t}" != "TidyTap-${tag#v}.dmg" ]]; then
  print -u2 -- "Pass a verified TidyTap release DMG and its matching version tag."
  exit 2
fi
"$project_root/Scripts/verify-dmg-sidecar.sh" "$release_dmg"

output="${release_dmg:h}/appcast.xml"
if [[ -e "$output" ]]; then
  print -u2 -- "The appcast candidate already exists; it was left unchanged."
  exit 1
fi

build_root="$project_root/build"
mkdir -p "$build_root"
candidate_dir=$(mktemp -d "$build_root/.update-feed.XXXXXX")
trap 'rm -rf "$candidate_dir"' EXIT
cp "$project_root/appcast.xml" "$candidate_dir/appcast.xml"
cp "$release_dmg" "$candidate_dir/${release_dmg:t}"

xcodebuild -quiet -project "$project_root/TidyTap.xcodeproj" -scheme TidyTap \
  -derivedDataPath "$build_root/update-tools" -resolvePackageDependencies >/dev/null
generate_appcast="$build_root/update-tools/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
generate_keys="$build_root/update-tools/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
if [[ ! -x "$generate_appcast" || ! -x "$generate_keys" ]]; then
  print -u2 -- "Pinned Sparkle generate_appcast tool is unavailable."
  exit 1
fi
public_key=$("$generate_keys" --account com.sharknia.TidyTap -p)
expected_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$project_root/Resources/AppInfo.plist")
if [[ "$public_key" != "$expected_key" ]]; then
  print -u2 -- "The Keychain signing key does not match the app's public update key."
  exit 1
fi

"$generate_appcast" --account com.sharknia.TidyTap --maximum-deltas 0 \
  --download-url-prefix "https://github.com/Sharknia/TidyTap/releases/download/$tag/" \
  --link "https://github.com/Sharknia/TidyTap/releases/tag/$tag" \
  "$candidate_dir"

/usr/bin/xmllint --noout "$candidate_dir/appcast.xml"
/usr/bin/grep -Fq 'sparkle:edSignature=' "$candidate_dir/appcast.xml"
/usr/bin/grep -Fq "releases/download/$tag/" "$candidate_dir/appcast.xml"
mv "$candidate_dir/appcast.xml" "$output"
print -- "Prepared appcast candidate with a signed update: $output"
