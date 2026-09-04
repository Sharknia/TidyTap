#!/bin/zsh
# Create a signed, notarized direct-distribution DMG. Credentials remain in the
# local keychain and ignored LocalSigning.xcconfig.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

local_signing_config="$project_root/Config/LocalSigning.xcconfig"
configuration="Release"
build_root="$project_root/build"
output_dir="$build_root/artifacts"
mkdir -p "$build_root"

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

if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "$identity"; then
  print -u2 -- "The configured Developer ID Application identity is unavailable in this keychain."
  exit 2
fi
if ! /usr/bin/xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
  print -u2 -- "The configured notarytool keychain profile is unavailable or unusable."
  exit 2
fi

candidate_dir=$(mktemp -d "$build_root/.release-candidate.XXXXXX")
step_number=0
publication_lock=""

cleanup() {
  if [[ -n "$publication_lock" && -d "$publication_lock" ]]; then
    rmdir "$publication_lock"
  fi
  rm -rf "$candidate_dir"
}
trap cleanup EXIT

print_sanitized_log() {
  local log_path="$1"
  TIDYTAP_PROJECT_ROOT="$project_root" \
    TIDYTAP_IDENTITY="$identity" \
    TIDYTAP_TEAM_ID="$team_id" \
    TIDYTAP_NOTARY_PROFILE="$notary_profile" \
    /usr/bin/perl -ne '
      BEGIN {
        $root = $ENV{TIDYTAP_PROJECT_ROOT};
        $identity = $ENV{TIDYTAP_IDENTITY};
        $team = $ENV{TIDYTAP_TEAM_ID};
        $profile = $ENV{TIDYTAP_NOTARY_PROFILE};
        $count = 0;
      }
      s/\Q$root\E/<project>/g;
      s/\Q$identity\E/<signing-identity>/g;
      s/\Q$team\E/<team-id>/g;
      s/\Q$profile\E/<notary-profile>/g;
      s{/(?:Users|private/var/folders|var/folders)/[^\s:]+}{<local-path>}g;
      s/[\r\n]+//g;
      $_ = substr($_, 0, 400) . "...\n" if length($_) > 400;
      print;
      last if ++$count >= 25;
    ' "$log_path"
}

run_step() {
  local label="$1"
  local hint="$2"
  shift 2
  ((step_number += 1))
  local log_path="$candidate_dir/step-$step_number.log"

  if ! "$@" >"$log_path" 2>&1; then
    print -u2 -- "$label failed. $hint"
    print_sanitized_log "$log_path" >&2
    exit 1
  fi
}

run_step \
  "Release signing settings verification" \
  "Check the ignored local signing configuration." \
  "$project_root/Scripts/verify-release-build-settings.sh" --require-local

archive_path="$candidate_dir/TidyTap.xcarchive"
run_step \
  "Release archive" \
  "Check the Release build settings and source errors." \
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
  print -u2 -- "Release archive did not contain TidyTap.app with its embedded TidyTapHelper.app."
  exit 1
fi

verify_signed_bundle() {
  local bundle_path="$1"
  local signature_details

  run_step \
    "Code signature verification" \
    "Check that both app bundles were signed by the configured Developer ID." \
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

dmg_name="TidyTap-$version.dmg"
candidate_dmg="$candidate_dir/$dmg_name"
staging_dir="$candidate_dir/staging"
mkdir "$staging_dir"
/usr/bin/ditto "$app_path" "$staging_dir/TidyTap.app"
run_step \
  "Release DMG creation" \
  "Check available disk space and the archived app bundle." \
  /usr/bin/hdiutil create -volname "TidyTap" -srcfolder "$staging_dir" -ov -format UDZO "$candidate_dmg"

run_step \
  "Notarization submission" \
  "Check Apple notarization service availability and the local keychain profile." \
  /usr/bin/xcrun notarytool submit "$candidate_dmg" --keychain-profile "$notary_profile" --wait
run_step \
  "Notarization stapling" \
  "Apple accepted the candidate, but its ticket could not be attached." \
  /usr/bin/xcrun stapler staple "$candidate_dmg"
run_step \
  "Stapled ticket validation" \
  "The attached notarization ticket did not validate." \
  /usr/bin/xcrun stapler validate "$candidate_dmg"
run_step \
  "Gatekeeper assessment" \
  "The notarized candidate was not accepted by Gatekeeper." \
  /usr/sbin/spctl --assess --type open --context context:primary-signature -vv "$candidate_dmg"

candidate_sidecar="$candidate_dmg.sha256"
(
  cd "$candidate_dir"
  /usr/bin/shasum -a 256 "$dmg_name" > "${dmg_name}.sha256"
)
run_step \
  "Release checksum verification" \
  "The candidate DMG changed while it was being packaged." \
  "$project_root/Scripts/verify-dmg-sidecar.sh" "$candidate_dmg"

mkdir -p "$output_dir"
final_dir="$output_dir/${dmg_name:r}"
publication_lock="$output_dir/.${dmg_name:r}.lock"
if ! mkdir "$publication_lock"; then
  print -u2 -- "Another package operation is already preparing this version."
  exit 1
fi
if [[ -e "$final_dir" || -L "$final_dir" ]]; then
  print -u2 -- "A release package for this version already exists; it was left unchanged."
  exit 1
fi

publication_dir="$candidate_dir/publication"
mkdir "$publication_dir"
mv "$candidate_dmg" "$publication_dir/$dmg_name"
mv "$candidate_sidecar" "$publication_dir/${dmg_name}.sha256"
# This same-filesystem directory rename exposes the DMG and sidecar together.
mv "$publication_dir" "$final_dir"
rmdir "$publication_lock"
publication_lock=""

relative_dmg="build/artifacts/${dmg_name:r}/$dmg_name"
checksum=$(cut -d ' ' -f 1 "$final_dir/${dmg_name}.sha256")
print -- "Created notarized Release DMG: $relative_dmg"
print -- "SHA-256: $checksum"
