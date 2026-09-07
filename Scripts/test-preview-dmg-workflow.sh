#!/bin/zsh
# Static contracts plus source/publication checks in disposable Git fixtures.
# No real build, signing, mounting, installation, or release publication.
set -euo pipefail

project_root="${0:A:h:h}"
preview_script="$project_root/Scripts/package-preview-dmg.sh"
installer_script="$project_root/Scripts/create-installer-dmg.sh"
installer_settings="$project_root/Scripts/dmgbuild-settings.py"
installer_requirements="$project_root/Scripts/dmgbuild-requirements.txt"

require_source() {
  local pattern="$1"
  if ! /usr/bin/grep -Eq -- "$pattern" "$preview_script"; then
    print -u2 -- "Missing expected preview workflow contract: $pattern"
    exit 1
  fi
}

forbidden_source() {
  local pattern="$1"
  if /usr/bin/grep -Eq -- "$pattern" "$preview_script"; then
    print -u2 -- "Preview workflow must not contain: $pattern"
    exit 1
  fi
}

# The no-argument entry point remains the existing local ad-hoc path.
require_source 'if \(\( \$# == 0 \)\); then'
require_source 'CODE_SIGNING_ALLOWED=NO'
require_source '/usr/bin/codesign --force --sign - --timestamp=none "\$bundle_path"'
require_source 'dmg_name="TidyTap-\$version-preview-adhoc\.dmg"'
require_source 'Scripts/create-installer-dmg\.sh'
require_source '--source-directory "\$source_directory"'
require_source 'Mounted preview DMG must expose only Applications and TidyTap\.app'
forbidden_source 'Install TidyTap\.txt'
forbidden_source '/usr/bin/hdiutil create'

# Developer ID mode must be explicit, use the passed ignored config during the
# build, and never replace the build's signatures with an ad-hoc signature.
require_source 'Usage: .*--developer-id-config'
require_source 'developer_id_config="\$\{2:A\}"'
require_source 'TIDYTAP_DEVELOPMENT_TEAM'
require_source 'TIDYTAP_DEVELOPER_ID_APPLICATION'
require_source '/usr/bin/security find-identity -v -p codesigning'
require_source '-xcconfig "\$developer_id_config"'
require_source 'Do not replace them with an'
require_source 'Developer ID preview helper" "TidyTapHelper"'
require_source 'Developer ID preview app" "com\.sharknia\.TidyTap"'
require_source 'Copied Developer ID preview helper" "TidyTapHelper"'
require_source 'Copied Developer ID preview app" "com\.sharknia\.TidyTap"'
require_source 'dmg_name="TidyTap-\$version-preview-developer-id-\$commit\.dmg"'

# A candidate must prove the Developer ID chain/team, app seal, copied app,
# container signature, and checksum before the atomic no-overwrite publication.
require_source 'Authority=Developer ID Certification Authority'
require_source 'Authority=Apple Root CA'
require_source 'TeamIdentifier=\$team_id'
require_source "designated =>"
require_source 'anchor apple generic'
require_source 'certificate leaf\[subject\.OU\] = \$team_id'
require_source 'Developer ID preview app resource seal verification'
require_source 'Copied Developer ID preview app resource seal verification'
require_source 'Developer ID preview DMG signing'
require_source 'Scripts/verify-dmg-sidecar\.sh'
require_source 'if \[\[ -e "\$final_dir" \|\| -L "\$final_dir" \]\]; then'
require_source 'mv "\$publication_dir" "\$final_dir"'

# This is intentionally a local preview path, never a release transport.
forbidden_source '/usr/bin/xcrun notarytool'
forbidden_source '/usr/bin/xcrun stapler'
forbidden_source '/usr/sbin/spctl'
forbidden_source 'gh[[:space:]]+release'
forbidden_source 'git[[:space:]]+tag'

for required_file in "$installer_script" "$installer_settings" "$installer_requirements"; do
  [[ -f "$required_file" ]] || { print -u2 -- "Missing installer layout file: $required_file"; exit 1; }
done
if [[ ! -f "$project_root/Resources/DMGBackground.tiff" ]]; then
  print -u2 -- "Missing committed installer background."
  exit 1
fi
if ! /usr/bin/grep -Fqx 'dmgbuild==1.6.7' "$installer_requirements" || \
  ! /usr/bin/grep -Fqx 'ds-store==1.3.3' "$installer_requirements" || \
  ! /usr/bin/grep -Fqx 'mac-alias==2.2.3' "$installer_requirements"; then
  print -u2 -- "Installer dependency pins changed unexpectedly."
  exit 1
fi
if ! /usr/bin/grep -Fq 'requires Python 3.10 or newer' "$installer_script" || \
  ! /usr/bin/grep -Fq 'build/.dmgbuild-venv' "$installer_script" || \
  ! /usr/bin/grep -Fq -- '--index-url https://pypi.org/simple' "$installer_script"; then
  print -u2 -- "Installer helper must use a compatible, isolated PyPI venv."
  exit 1
fi
if /usr/bin/grep -Eq 'osascript' "$installer_script"; then
  print -u2 -- "Installer helper must not automate Finder."
  exit 1
fi
if zsh "$installer_script" >/dev/null 2>&1; then
  print -u2 -- "Installer helper accepted missing required arguments."
  exit 1
fi
/usr/bin/python3 "$project_root/Scripts/test-installer-dmg-layout.py"

# The argument parser fails before it can build when the explicit value is
# missing; this is a no-side-effect CLI regression check.
if zsh "$preview_script" --developer-id-config >/dev/null 2>&1; then
  print -u2 -- "Developer ID preview accepted a missing config path."
  exit 1
fi

# Exercise the actual source guard and publication tail with real Git and a
# fake build in between. Extract only those sections: credentials and Apple
# commands are never run, and production needs no test-only command overrides.
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/tidytap-preview-source.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT
/usr/bin/awk '/^# Source identity is captured/,/^read_xcconfig_value\(\)/ { if ($0 !~ /^read_xcconfig_value\(\)/) print }' "$preview_script" > "$fixture_root/source-guard.zsh"
/usr/bin/awk '/^cleanup\(\)/,/^trap cleanup EXIT/' "$preview_script" > "$fixture_root/cleanup.zsh"
/usr/bin/awk '/^run_step\(\)/,/^}/' "$preview_script" > "$fixture_root/run-step.zsh"
/usr/bin/awk '/^  sources_dir=/,/^  # The passed file/ { if ($0 !~ /^  # The passed file/) print }' "$preview_script" > "$fixture_root/snapshot.zsh"
/usr/bin/awk '/^mkdir -p "\$output_dir"/ { emit=1 } emit' "$preview_script" > "$fixture_root/publication.zsh"
require_source '-project "\$sources_dir/TidyTap\.xcodeproj"'
require_source '/usr/bin/git archive .* "\$source_commit"'

# Keep the extracted guard before the real build and the final check directly
# before the atomic move. This catches relocating checks outside these seams.
/usr/bin/awk '
  /^  source_commit=/ { capture=NR }
  /^derived_data=/ { if (!capture || capture >= NR) exit 1; build=NR }
  /^  require_unchanged_preview_source$/ { last_guard=NR; guards++ }
  /^mv "\$publication_dir" "\$final_dir"/ {
    if (!build || guards != 2 || last_guard != NR-2) exit 1; checked=1
  }
  END { if (!checked) exit 1 }
' "$preview_script"
forbidden_source 'rev-parse --verify --short=12 HEAD'

run_source_case() {
  local scenario="$1" initial="$2" late="$3" expected="$4"
  local repo="$fixture_root/$scenario"
  mkdir "$repo"
  (
    cd "$repo"
    /usr/bin/git init -q
    /usr/bin/git config user.name 'Preview Fixture'
    /usr/bin/git config user.email 'preview@example.invalid'
    /usr/bin/git config commit.gpgsign false
    print -r -- 'build/' > .gitignore
    print -r -- 'Config/LocalSigning.xcconfig' >> .gitignore
    print -r -- 'Sources/Ignored.swift' >> .gitignore
    mkdir Sources
    print -r -- '// committed Swift source' > Sources/Tracked.swift
    print -r -- 'original' > tracked.txt
    /usr/bin/git add .
    /usr/bin/git commit -qm initial
    case "$initial" in
      tracked) print -r -- 'changed' >> tracked.txt ;;
      staged) print -r -- 'changed' >> tracked.txt; /usr/bin/git add tracked.txt ;;
      untracked) print -r -- 'new' > untracked.txt ;;
      ignored)
        mkdir -p Config build
        print -r -- '// ignored Swift source' > Sources/Ignored.swift
        print -r -- '// inert config fixture, no credentials' > Config/LocalSigning.xcconfig
        print -r -- 'old build output' > build/existing-output
        ;;
    esac
  )
  local result=0
  (
    cd "$repo"
    developer_id_config='unused-fixture-config'
    developer_id_preview=true
    preview_label='Developer ID local preview'
    source "$fixture_root/source-guard.zsh"
    # Fake build: produce inert files only, then simulate an editor or checkout.
    mkdir -p build
    candidate_dir=$(mktemp -d "$repo/build/.preview-candidate.XXXXXX")
    publication_lock=""
    mounted_image=false
    source "$fixture_root/cleanup.zsh"
    step_number=0
    # Run the production archive/extraction commands on this fixture's HEAD.
    print_sanitized_log() { print -u2 -- 'Fixture snapshot command failed.'; }
    source "$fixture_root/run-step.zsh"
    source "$fixture_root/snapshot.zsh"
    if [[ ! -f "$sources_dir/Sources/Tracked.swift" ||
          -e "$sources_dir/Sources/Ignored.swift" ||
          -e "$sources_dir/Config/LocalSigning.xcconfig" ||
          -e "$sources_dir/build" ]]; then
      print -u2 -- 'Snapshot did not contain only committed fixture sources.'
      exit 1
    fi
    touch build/build-started
    dmg_name="TidyTap-0.1.0-preview-developer-id-$commit.dmg"
    candidate_dmg="$candidate_dir/$dmg_name"
    candidate_sidecar="$candidate_dmg.sha256"
    print -r -- 'fake disk image' > "$candidate_dmg"
    print -r -- "fixture-checksum  $dmg_name" > "$candidate_sidecar"
    case "$late" in
      tracked) print -r -- 'changed' >> tracked.txt ;;
      untracked) print -r -- 'new' > untracked.txt ;;
      head) /usr/bin/git -c core.hooksPath=/dev/null commit --allow-empty -qm moved ;;
    esac
    output_dir="$repo/build/artifacts"
    source "$fixture_root/publication.zsh"
  ) > "$fixture_root/$scenario.log" 2>&1 || result=$?
  if [[ "$expected" == success ]]; then
    local original_commit=$(/usr/bin/git -C "$repo" rev-parse HEAD)
    local expected_name="TidyTap-0.1.0-preview-developer-id-${original_commit[1,12]}"
    [[ $result == 0 && -f "$repo/build/artifacts/$expected_name/$expected_name.dmg" ]] || {
      print -u2 -- "Clean source fixture failed: $scenario"
      /bin/cat "$fixture_root/$scenario.log" >&2
      exit 1
    }
  else
    if (( result == 0 )) || ! /usr/bin/grep -Fq 'unchanged HEAD and clean tracked/untracked worktree' "$fixture_root/$scenario.log"; then
      print -u2 -- "Source guard failed to reject: $scenario"; exit 1
    fi
    local leftovers=("$repo"/build/artifacts/*(DN) "$repo"/build/.preview-candidate.*(DN))
    if (( ${#leftovers} != 0 )); then
      print -u2 -- "Rejected source left a candidate or publication lock: $scenario"; exit 1
    fi
    if [[ "$initial" != clean && -e "$repo/build/build-started" ]]; then
      print -u2 -- "Dirty source reached the build: $scenario"; exit 1
    fi
  fi
}

run_source_case clean clean none success
run_source_case ignored-source-and-local-files ignored none success
run_source_case dirty-tracked tracked none failure
run_source_case dirty-staged staged none failure
run_source_case dirty-untracked untracked none failure
run_source_case changed-tracked clean tracked failure
run_source_case changed-untracked clean untracked failure
run_source_case changed-head clean head failure

print -- "Preview DMG workflow checks passed, including Finder metadata settings and eight snapshot/source/publication fixtures."
