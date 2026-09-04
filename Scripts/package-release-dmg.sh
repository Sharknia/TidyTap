#!/bin/zsh
# Create a signed, notarized direct-distribution DMG using credentials that
# remain in the local keychain and ignored LocalSigning.xcconfig.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

local_signing_config="$project_root/Config/LocalSigning.xcconfig"
configuration="Release"
archive_path="$project_root/build/TidyTap.xcarchive"
output_dir="$project_root/build/artifacts"

read_xcconfig_value() {
  local key="$1"
  /usr/bin/awk -v key="$key" '
    /^[[:space:]]*\/\// { next }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]*(//.*)?$", "")
      print
      exit
    }
  ' "$local_signing_config"
}

require_value() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *'$('* || "$value" == *'${'* ]]; then
    print -u2 -- "Missing or unresolved $key in Config/LocalSigning.xcconfig."
    exit 2
  fi
}

if [[ ! -f "$local_signing_config" ]]; then
  print -u2 -- "Missing Config/LocalSigning.xcconfig. Copy Config/LocalSigning.xcconfig.example and fill the local values."
  exit 2
fi

team_id=$(read_xcconfig_value TIDYTAP_DEVELOPMENT_TEAM)
identity=$(read_xcconfig_value TIDYTAP_DEVELOPER_ID_APPLICATION)
notary_profile=$(read_xcconfig_value TIDYTAP_NOTARYTOOL_KEYCHAIN_PROFILE)
require_value TIDYTAP_DEVELOPMENT_TEAM "$team_id"
require_value TIDYTAP_DEVELOPER_ID_APPLICATION "$identity"
require_value TIDYTAP_NOTARYTOOL_KEYCHAIN_PROFILE "$notary_profile"

if [[ ! "$team_id" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 -- "TIDYTAP_DEVELOPMENT_TEAM must be a 10-character Apple Team ID."
  exit 2
fi
if [[ "$identity" != "Developer ID Application:"* || "$identity" != *"($team_id)" ]]; then
  print -u2 -- "TIDYTAP_DEVELOPER_ID_APPLICATION must be a Developer ID Application identity for TIDYTAP_DEVELOPMENT_TEAM."
  exit 2
fi

# Do not display identities or profiles: neither is needed in successful output.
if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "$identity"; then
  print -u2 -- "The configured Developer ID Application identity is unavailable in this keychain."
  exit 2
fi
if ! /usr/bin/xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
  print -u2 -- "The configured notarytool keychain profile is unavailable or unusable."
  exit 2
fi

"$project_root/Scripts/verify-release-build-settings.sh" --require-local

rm -rf "$archive_path"
mkdir -p "$output_dir"
xcodebuild \
  -quiet \
  -project TidyTap.xcodeproj \
  -scheme TidyTap \
  -configuration "$configuration" \
  -archivePath "$archive_path" \
  archive

app_path="$archive_path/Products/Applications/TidyTap.app"
helper_path="$app_path/Contents/Library/LoginItems/TidyTapHelper.app"
if [[ ! -d "$app_path" || ! -d "$helper_path" ]]; then
  print -u2 -- "Archive did not contain TidyTap.app with its embedded TidyTapHelper.app."
  exit 1
fi

verify_signed_bundle() {
  local bundle_path="$1"
  local signature_details

  /usr/bin/codesign --verify --strict --verbose=2 "$bundle_path"
  signature_details=$(/usr/bin/codesign -dvv "$bundle_path" 2>&1)
  if ! /usr/bin/grep -Fqx "Authority=$identity" <<<"$signature_details" || \
    ! /usr/bin/grep -Fqx "TeamIdentifier=$team_id" <<<"$signature_details"; then
    print -u2 -- "A bundle was not signed by the configured Developer ID team."
    exit 1
  fi
}

# Verify both independently. --deep alone can hide an incorrectly signed helper.
verify_signed_bundle "$helper_path"
verify_signed_bundle "$app_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ -z "$version" ]]; then
  print -u2 -- "Could not determine the app version."
  exit 1
fi

dmg_path="$output_dir/TidyTap-$version.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/TidyTap-release.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$app_path" "$staging_dir/TidyTap.app"
/usr/bin/hdiutil create -volname "TidyTap" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"

/usr/bin/xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
/usr/bin/xcrun stapler staple "$dmg_path"
/usr/bin/xcrun stapler validate "$dmg_path"
/usr/sbin/spctl --assess --type open --context context:primary-signature -vv "$dmg_path"
/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

print -- "Created notarized Release DMG: $dmg_path"
print -- "SHA-256: $(cut -d ' ' -f 1 "$dmg_path.sha256")"
