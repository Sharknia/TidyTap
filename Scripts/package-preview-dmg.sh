#!/bin/zsh
# Build an ad-hoc-signed local preview DMG. It is deliberately not a public release.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

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
  TIDYTAP_PROJECT_ROOT="$project_root" /usr/bin/perl -ne '
    BEGIN { $root = $ENV{TIDYTAP_PROJECT_ROOT}; $count = 0; }
    s/\Q$root\E/<project>/g;
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

# Sign nested code first so the parent app's resource seal includes it.
sign_preview_bundle "$helper_path" "Preview helper"
sign_preview_bundle "$app_path" "Preview app"
verify_preview_bundle "$helper_path" "Preview helper"
run_step \
  "Preview app deep signature verification" \
  "The app or its embedded helper is not a valid sealed bundle." \
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ -z "$version" ]]; then
  print -u2 -- "Could not determine the app version."
  exit 1
fi

dmg_name="TidyTap-$version-preview-adhoc.dmg"
candidate_dmg="$candidate_dir/$dmg_name"
staging_dir="$candidate_dir/staging"
mkdir "$staging_dir"
/usr/bin/ditto "$app_path" "$staging_dir/TidyTap.app"
/bin/ln -s /Applications "$staging_dir/Applications"
/usr/bin/tee "$staging_dir/Install TidyTap.txt" >/dev/null <<'EOF'
TidyTap 설치 / Install TidyTap

TidyTap.app을 Applications 폴더로 드래그하세요.
Drag TidyTap.app to the Applications folder.
EOF
run_step \
  "Preview DMG creation" \
  "Check available disk space and the built app bundle." \
  /usr/bin/hdiutil create -volname "TidyTap Preview" -srcfolder "$staging_dir" -ov -format UDZO "$candidate_dmg"

mkdir "$mount_dir"
run_step \
  "Preview DMG mount" \
  "The candidate DMG could not be mounted read-only for install verification." \
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$candidate_dmg"
mounted_image=true

applications_target=$(/usr/bin/readlink "$mount_dir/Applications" 2>/dev/null || true)
if [[ ! -L "$mount_dir/Applications" || "$applications_target" != "/Applications" ]]; then
  print -u2 -- "Mounted preview DMG did not contain the /Applications install link."
  exit 1
fi
if [[ ! -f "$mount_dir/Install TidyTap.txt" ]]; then
  print -u2 -- "Mounted preview DMG did not contain the install instructions."
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
verify_preview_bundle "$copied_helper_path" "Copied preview helper"
run_step \
  "Copied preview app deep signature verification" \
  "The copied app or embedded helper did not retain a valid resource seal." \
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$copied_app_path"
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
  print -u2 -- "Another package operation is already preparing this version."
  exit 1
fi
if [[ -e "$final_dir" || -L "$final_dir" ]]; then
  print -u2 -- "An ad-hoc preview package for this version already exists; it was left unchanged."
  exit 1
fi

publication_dir="$candidate_dir/publication"
mkdir "$publication_dir"
mv "$candidate_dmg" "$publication_dir/$dmg_name"
mv "$candidate_sidecar" "$publication_dir/${dmg_name}.sha256"
mv "$publication_dir" "$final_dir"
rmdir "$publication_lock"
publication_lock=""

relative_dmg="build/artifacts/${dmg_name:r}/$dmg_name"
checksum=$(cut -d ' ' -f 1 "$final_dir/${dmg_name}.sha256")
print -- "Created ad-hoc preview DMG: $relative_dmg"
print -- "SHA-256: $checksum"
