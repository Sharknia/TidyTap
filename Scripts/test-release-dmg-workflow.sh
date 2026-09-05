#!/bin/zsh
# Static regression checks for the public-DMG signing order. This deliberately
# never builds, signs, notarizes, installs, or publishes an artifact.
set -euo pipefail

project_root="${0:A:h:h}"
release_script="$project_root/Scripts/package-release-dmg.sh"

require_line() {
  local pattern="$1"
  local line
  line=$(/usr/bin/grep -n -m 1 -E "$pattern" "$release_script" | /usr/bin/cut -d : -f 1 || true)
  if [[ -z "$line" ]]; then
    print -u2 -- "Missing expected release workflow step: $pattern"
    exit 1
  fi
  print -- "$line"
}

assert_before() {
  local earlier_pattern="$1"
  local later_pattern="$2"
  local earlier_line later_line
  earlier_line=$(require_line "$earlier_pattern")
  later_line=$(require_line "$later_pattern")
  if (( earlier_line >= later_line )); then
    print -u2 -- "Release workflow order is unsafe: $earlier_pattern must precede $later_pattern."
    exit 1
  fi
}

# The DMG must be signed and fully verified before Apple's submission command.
assert_before '"Release DMG signing"' '"Notarization submission"'
assert_before 'verify_developer_id_signature "\$candidate_dmg" "Release DMG"' '"Notarization submission"'
assert_before 'Timestamp=.+' '"Notarization submission"'

signature_verifier_body=$(/usr/bin/awk '/^verify_developer_id_signature\(\)/,/^}/' "$release_script")
if ! /usr/bin/grep -Fq 'Authority=$identity' <<<"$signature_verifier_body" || \
  ! /usr/bin/grep -Fq 'TeamIdentifier=$team_id' <<<"$signature_verifier_body"; then
  print -u2 -- "The DMG signature verifier does not enforce the configured identity and team."
  exit 1
fi

# A timestamped Developer ID codesign command is required for the container.
if ! /usr/bin/grep -Fq '/usr/bin/codesign --force --sign "$identity" --timestamp "$candidate_dmg"' "$release_script"; then
  print -u2 -- "The DMG is not signed with the configured identity and secure timestamp."
  exit 1
fi

# run_step exits on any command failure; publication is structurally later than
# all DMG-signing checks. This proves a signing/verification failure cannot
# reach the atomic publication move, without invoking real Apple services.
run_step_body=$(/usr/bin/awk '/^run_step\(\)/,/^}/' "$release_script")
if ! /usr/bin/grep -Fq 'if ! "$@" >"$log_path" 2>&1; then' <<<"$run_step_body" || \
  ! /usr/bin/grep -Fq 'exit 1' <<<"$run_step_body"; then
  print -u2 -- "Release step failures are not fail-closed."
  exit 1
fi
assert_before '"Release DMG signing"' 'mv "\$publication_dir" "\$final_dir"'
assert_before 'verify_developer_id_signature "\$candidate_dmg" "Release DMG"' 'mv "\$publication_dir" "\$final_dir"'
assert_before 'Timestamp=.+' 'mv "\$publication_dir" "\$final_dir"'

print -- "Release DMG signing workflow regression checks passed."
