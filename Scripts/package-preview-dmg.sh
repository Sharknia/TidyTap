#!/bin/zsh
# Build a local preview DMG. The default path is ad-hoc signed; an explicitly
# supplied ignored xcconfig enables a Developer ID-signed, non-notarized preview.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

usage() {
  print -u2 -- "Usage: ${0:t} [--developer-id-config path/to/LocalSigning.xcconfig]"
}

developer_id_config=""
if (( $# == 0 )); then
  : # Keep the established ad-hoc preview as the default.
elif (( $# == 2 )) && [[ "$1" == "--developer-id-config" ]]; then
  developer_id_config="${2:A}"
else
  usage
  exit 2
fi

developer_id_preview=false
identity=""
team_id=""

# Source identity is captured before any build work and checked again at the
# publication boundary. Ignored signing config and build output are permitted.
require_unchanged_preview_source() {
  local current_head tree_status
  current_head=$(/usr/bin/git rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || {
    print -u2 -- "Could not determine the Developer ID preview source commit."
    exit 1
  }
  tree_status=$(/usr/bin/git status --porcelain=v1 --untracked-files=all --ignore-submodules=none 2>/dev/null) || {
    print -u2 -- "Could not check the Developer ID preview worktree."
    exit 1
  }
  if [[ "$current_head" != "$source_commit" || -n "$tree_status" ]]; then
    print -u2 -- "Developer ID preview requires an unchanged HEAD and clean tracked/untracked worktree; no candidate was published."
    exit 1
  fi
}

if [[ -n "$developer_id_config" ]]; then
  source_commit=$(/usr/bin/git rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || {
    print -u2 -- "Could not determine the Developer ID preview source commit."
    exit 1
  }
  require_unchanged_preview_source
  commit="${source_commit[1,12]}"
fi

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
  ' "$developer_id_config"
}

require_config_value() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *'$('* || "$value" == *'${'* ]]; then
    print -u2 -- "Missing or unresolved $key in the Developer ID preview config."
    exit 2
  fi
}

if [[ -n "$developer_id_config" ]]; then
  if [[ ! -f "$developer_id_config" ]]; then
    print -u2 -- "Developer ID preview config does not exist or is not a regular file."
    exit 2
  fi

  team_id=$(read_xcconfig_value TIDYTAP_DEVELOPMENT_TEAM)
  identity=$(read_xcconfig_value TIDYTAP_DEVELOPER_ID_APPLICATION)
  require_config_value TIDYTAP_DEVELOPMENT_TEAM "$team_id"
  require_config_value TIDYTAP_DEVELOPER_ID_APPLICATION "$identity"
  if [[ ! "$team_id" =~ '^[A-Z0-9]{10}$' ]]; then
    print -u2 -- "Developer ID preview config has an invalid Apple Team ID."
    exit 2
  fi
  if [[ "$identity" != "Developer ID Application:"* || "$identity" != *"($team_id)" ]]; then
    print -u2 -- "Developer ID preview config does not pair its Developer ID identity with its Team ID."
    exit 2
  fi
  if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "$identity"; then
    print -u2 -- "The configured Developer ID Application identity is unavailable in this keychain."
    exit 2
  fi
  developer_id_preview=true
fi

configuration="Release"
build_root="$project_root/build"
output_dir="$build_root/artifacts"
mkdir -p "$build_root"
candidate_dir=$(mktemp -d "$build_root/.preview-candidate.XXXXXX")
step_number=0
publication_lock=""
mount_dir="$candidate_dir/mounted-dmg"
mounted_image=false

cleanup() {
  if $mounted_image; then
    /usr/bin/hdiutil detach -force "$mount_dir" >/dev/null 2>&1 || true
  fi
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
    /usr/bin/perl -ne '
      BEGIN {
        $root = $ENV{TIDYTAP_PROJECT_ROOT};
        $identity = $ENV{TIDYTAP_IDENTITY};
        $team = $ENV{TIDYTAP_TEAM_ID};
        $count = 0;
      }
      s/\Q$root\E/<project>/g;
      s/\Q$identity\E/<signing-identity>/g if length $identity;
      s/\Q$team\E/<team-id>/g if length $team;
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

derived_data="$candidate_dir/derived-data"
if $developer_id_preview; then
  sources_dir="$candidate_dir/sources"
  mkdir "$sources_dir"
  run_step \
    "Developer ID preview source archive" \
    "Check that the captured source commit is available." \
    /usr/bin/git archive --format=tar --output="$candidate_dir/sources.tar" "$source_commit"
  run_step \
    "Developer ID preview source extraction" \
    "Check available disk space for the committed source snapshot." \
    /usr/bin/tar -xf "$candidate_dir/sources.tar" -C "$sources_dir"
  # The passed file is the existing ignored local config. It overrides only its
  # local values; the target's Release settings and Config/Signing.xcconfig
  # still supply manual signing, hardened runtime, bundle IDs, and timestamping.
  run_step \
    "Developer ID preview build" \
    "Check the Release build settings, source errors, and local signing identity." \
    xcodebuild \
      -quiet \
      -project "$sources_dir/TidyTap.xcodeproj" \
      -scheme TidyTap \
      -configuration "$configuration" \
      -derivedDataPath "$derived_data" \
      -xcconfig "$developer_id_config" \
      build
  source_directory="$sources_dir"
else
  run_step \
    "Preview build" \
    "Check the Release build settings and source errors." \
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
  source_directory="$project_root"
fi

app_path="$derived_data/Build/Products/$configuration/TidyTap.app"
helper_path="$app_path/Contents/MacOS/TidyTapHelper"
if [[ ! -d "$app_path" || ! -x "$helper_path" ]]; then
  print -u2 -- "Preview build did not produce TidyTap.app with its embedded TidyTapHelper executable."
  exit 1
fi

sign_preview_bundle() {
  local bundle_path="$1"
  local label="$2"
  run_step \
    "$label ad-hoc signing" \
    "Check that the bundle contains only signable local build output." \
    /usr/bin/codesign --force --sign - --timestamp=none "$bundle_path"
}

verify_preview_bundle() {
  local bundle_path="$1"
  local label="$2"
  run_step \
    "$label signature verification" \
    "The ad-hoc resource seal or executable signature is invalid." \
    /usr/bin/codesign --verify --strict --verbose=2 "$bundle_path"
}

verify_developer_id_signature() {
  local artifact_path="$1"
  local artifact_label="$2"
  local expected_identifier="${3:-}"
  local signature_details
  local designated_requirement

  run_step \
    "$artifact_label signature verification" \
    "Check that the artifact was signed by the configured Developer ID." \
    /usr/bin/codesign --verify --strict --verbose=2 "$artifact_path"
  signature_details=$(/usr/bin/codesign -dvv "$artifact_path" 2>&1)
  if ! /usr/bin/grep -Fqx "Authority=$identity" <<<"$signature_details" || \
    ! /usr/bin/grep -Fqx "Authority=Developer ID Certification Authority" <<<"$signature_details" || \
    ! /usr/bin/grep -Fqx "Authority=Apple Root CA" <<<"$signature_details" || \
    ! /usr/bin/grep -Fqx "TeamIdentifier=$team_id" <<<"$signature_details"; then
    print -u2 -- "$artifact_label was not signed by the configured Developer ID certificate chain and team."
    exit 1
  fi
  if [[ -n "$expected_identifier" ]] && ! /usr/bin/grep -Fqx "Identifier=$expected_identifier" <<<"$signature_details"; then
    print -u2 -- "$artifact_label did not retain its expected bundle identifier."
    exit 1
  fi
  designated_requirement=$(/usr/bin/codesign -d -r- "$artifact_path" 2>&1)
  if ! /usr/bin/grep -Fq 'designated =>' <<<"$designated_requirement" || \
    ! /usr/bin/grep -Fq 'anchor apple generic' <<<"$designated_requirement" || \
    ! /usr/bin/grep -Fq "certificate leaf[subject.OU] = $team_id" <<<"$designated_requirement"; then
    print -u2 -- "$artifact_label did not retain the expected Developer ID designated-requirement style."
    exit 1
  fi
  if [[ -n "$expected_identifier" ]] && \
    ! /usr/bin/grep -Fq "identifier \"$expected_identifier\"" <<<"$designated_requirement" && \
    ! /usr/bin/grep -Fq "identifier $expected_identifier" <<<"$designated_requirement"; then
    print -u2 -- "$artifact_label designated requirement did not retain its expected signing identifier."
    exit 1
  fi
}

if $developer_id_preview; then
  # xcodebuild made the Developer ID signatures. Do not replace them with an
  # ad-hoc signature: that would change the identity macOS associates with AX/IM.
  verify_developer_id_signature "$helper_path" "Developer ID preview helper" "TidyTapHelper"
  verify_developer_id_signature "$app_path" "Developer ID preview app" "com.sharknia.TidyTap"
  run_step \
    "Developer ID preview app resource seal verification" \
    "The app or its embedded helper is not a valid sealed bundle." \
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
else
  # Sign nested code first so the parent app's resource seal includes it.
  sign_preview_bundle "$helper_path" "Preview helper"
  sign_preview_bundle "$app_path" "Preview app"
  verify_preview_bundle "$helper_path" "Preview helper"
  run_step \
    "Preview app deep signature verification" \
    "The app or its embedded helper is not a valid sealed bundle." \
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ -z "$version" ]]; then
  print -u2 -- "Could not determine the app version."
  exit 1
fi

if $developer_id_preview; then
  dmg_name="TidyTap-$version-preview-developer-id-$commit.dmg"
  volume_name="TidyTap Developer ID Preview"
  preview_label="Developer ID local preview"
else
  dmg_name="TidyTap-$version-preview-adhoc.dmg"
  volume_name="TidyTap Preview"
  preview_label="ad-hoc preview"
fi

candidate_dmg="$candidate_dir/$dmg_name"
run_step \
  "Preview DMG creation" \
  "Check the build-only Python environment, committed installer background, and built app bundle." \
  "$project_root/Scripts/create-installer-dmg.sh" \
    --source-directory "$source_directory" \
    --app "$app_path" \
    --volume-name "$volume_name" \
    --output "$candidate_dmg"

if $developer_id_preview; then
  run_step \
    "Developer ID preview DMG signing" \
    "Check that the configured Developer ID identity can sign disk images." \
    /usr/bin/codesign --force --sign "$identity" --timestamp "$candidate_dmg"
  verify_developer_id_signature "$candidate_dmg" "Developer ID preview DMG"
fi

mkdir "$mount_dir"
run_step \
  "Preview DMG mount" \
  "The candidate DMG could not be mounted read-only for install verification." \
  /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$candidate_dmg"
mounted_image=true

applications_target=$(/usr/bin/readlink "$mount_dir/응용 프로그램" 2>/dev/null || true)
if [[ ! -L "$mount_dir/응용 프로그램" || "$applications_target" != "/Applications" ]]; then
  print -u2 -- "Mounted preview DMG did not contain the /Applications install link."
  exit 1
fi
visible_items=("$mount_dir"/*(N))
if (( ${#visible_items} != 2 )); then
  print -u2 -- "Mounted preview DMG must expose only Applications and TidyTap.app."
  exit 1
fi

copied_app_path="$candidate_dir/installed-copy/TidyTap.app"
mkdir "${copied_app_path:h}"
run_step \
  "Preview app copy verification" \
  "The app could not be copied from the mounted DMG." \
  /usr/bin/ditto "$mount_dir/TidyTap.app" "$copied_app_path"
copied_helper_path="$copied_app_path/Contents/MacOS/TidyTapHelper"
if [[ ! -x "$copied_helper_path" ]]; then
  print -u2 -- "Mounted preview DMG did not contain TidyTap.app with its embedded helper."
  exit 1
fi
if $developer_id_preview; then
  verify_developer_id_signature "$copied_helper_path" "Copied Developer ID preview helper" "TidyTapHelper"
  verify_developer_id_signature "$copied_app_path" "Copied Developer ID preview app" "com.sharknia.TidyTap"
  run_step \
    "Copied Developer ID preview app resource seal verification" \
    "The copied app or embedded helper did not retain a valid resource seal." \
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$copied_app_path"
else
  verify_preview_bundle "$copied_helper_path" "Copied preview helper"
  run_step \
    "Copied preview app deep signature verification" \
    "The copied app or embedded helper did not retain a valid resource seal." \
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$copied_app_path"
fi
run_step \
  "Preview DMG detach" \
  "The isolated preview mount could not be detached." \
  /usr/bin/hdiutil detach "$mount_dir"
mounted_image=false

candidate_sidecar="$candidate_dmg.sha256"
(
  cd "$candidate_dir"
  /usr/bin/shasum -a 256 "$dmg_name" > "${dmg_name}.sha256"
)
run_step \
  "Preview checksum verification" \
  "The candidate DMG changed while it was being packaged." \
  "$project_root/Scripts/verify-dmg-sidecar.sh" "$candidate_dmg"

mkdir -p "$output_dir"
final_dir="$output_dir/${dmg_name:r}"
publication_lock="$output_dir/.${dmg_name:r}.lock"
if ! mkdir "$publication_lock"; then
  print -u2 -- "Another package operation is already preparing this preview candidate."
  exit 1
fi
if [[ -e "$final_dir" || -L "$final_dir" ]]; then
  if $developer_id_preview; then
    print -u2 -- "A Developer ID preview package for this version and commit already exists; it was left unchanged."
  else
    print -u2 -- "An ad-hoc preview package for this version already exists; it was left unchanged."
  fi
  exit 1
fi

publication_dir="$candidate_dir/publication"
mkdir "$publication_dir"
mv "$candidate_dmg" "$publication_dir/$dmg_name"
mv "$candidate_sidecar" "$publication_dir/${dmg_name}.sha256"
if $developer_id_preview; then
  require_unchanged_preview_source
fi
mv "$publication_dir" "$final_dir"
rmdir "$publication_lock"
publication_lock=""

relative_dmg="build/artifacts/${dmg_name:r}/$dmg_name"
checksum=$(cut -d ' ' -f 1 "$final_dir/${dmg_name}.sha256")
print -- "Created $preview_label DMG: $relative_dmg"
print -- "SHA-256: $checksum"
