#!/bin/zsh
# Static regression checks for the public-DMG signing order. This deliberately
# never builds, signs, notarizes, installs, or publishes an artifact.
set -euo pipefail

project_root="${0:A:h:h}"
release_script="$project_root/Scripts/package-release-dmg.sh"
artifact_verifier="$project_root/Scripts/verify-release-artifact.sh"

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

assert_container_codesign_order() {
  local codesign_line signing_step_start signing_step_window

  # Check the executable commands, rather than their human-readable run_step
  # labels: the exact timestamped codesign invocation must precede the exact
  # notarytool submission and atomic publication move.
  assert_before \
    '/usr/bin/codesign --force --sign "\$identity" --timestamp "\$candidate_dmg"' \
    '/usr/bin/xcrun notarytool submit "\$candidate_dmg" --keychain-profile "\$notary_profile" --wait'
  assert_before \
    '/usr/bin/codesign --force --sign "\$identity" --timestamp "\$candidate_dmg"' \
    'mv "\$publication_dir" "\$final_dir"'

  # The sign command itself must be run through run_step, which fails closed.
  codesign_line=$(require_line '/usr/bin/codesign --force --sign "\$identity" --timestamp "\$candidate_dmg"')
  signing_step_start=$(( codesign_line - 3 ))
  if (( signing_step_start < 1 )); then
    signing_step_start=1
  fi
  signing_step_window=$(/usr/bin/sed -n "${signing_step_start},${codesign_line}p" "$release_script")
  if ! /usr/bin/grep -Fq 'run_step \' <<<"$signing_step_window" || \
    ! /usr/bin/grep -Fq '"Release DMG signing"' <<<"$signing_step_window"; then
    print -u2 -- "The timestamped DMG codesign command is not a fail-closed release step."
    exit 1
  fi
}

if (( $# == 2 )) && [[ "$1" == "--check-order" ]]; then
  release_script="${2:A}"
  if [[ ! -f "$release_script" ]]; then
    print -u2 -- "Missing release workflow fixture."
    exit 2
  fi
  assert_container_codesign_order
  exit 0
elif (( $# != 0 )); then
  print -u2 -- "Usage: ${0:t} [--check-order path/to/package-release-dmg.sh]"
  exit 2
fi

assert_container_codesign_order

if ! /usr/bin/grep -Fq 'Scripts/create-installer-dmg.sh' "$release_script" || \
  ! /usr/bin/grep -Fq -- '--source-directory "$project_root"' "$release_script"; then
  print -u2 -- "Release workflow must use the shared committed-source installer helper."
  exit 1
fi
if /usr/bin/grep -Eq 'Install TidyTap|/usr/bin/hdiutil create' "$release_script"; then
  print -u2 -- "Release workflow must not create a text installer item or an unstyled hdiutil DMG."
  exit 1
fi
if ! /usr/bin/grep -Fq 'DMG must expose only Applications and TidyTap.app' "$artifact_verifier"; then
  print -u2 -- "Release artifact verification must enforce the two-item Finder contract."
  exit 1
fi

# The DMG must be signed and fully verified before Apple's submission command.
assert_before 'verify_developer_id_signature "\$candidate_dmg" "Release DMG"' '"Notarization submission"'
assert_before 'Timestamp=.+' '"Notarization submission"'

signature_verifier_body=$(/usr/bin/awk '/^verify_developer_id_signature\(\)/,/^}/' "$release_script")
if ! /usr/bin/grep -Fq 'Authority=$identity' <<<"$signature_verifier_body" || \
  ! /usr/bin/grep -Fq 'TeamIdentifier=$team_id' <<<"$signature_verifier_body"; then
  print -u2 -- "The DMG signature verifier does not enforce the configured identity and team."
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
assert_before 'verify_developer_id_signature "\$candidate_dmg" "Release DMG"' 'mv "\$publication_dir" "\$final_dir"'
assert_before 'Timestamp=.+' 'mv "\$publication_dir" "\$final_dir"'

# Negative mutation: an otherwise recognizable command sequence with codesign
# moved below notarytool must fail this same order checker. No release script or
# artifact is executed.
mutation_fixture=$(mktemp "${TMPDIR:-/tmp}/tidytap-release-order.XXXXXX")
trap 'rm -f "$mutation_fixture"' EXIT
print -- '/usr/bin/xcrun notarytool submit "$candidate_dmg" --keychain-profile "$notary_profile" --wait' > "$mutation_fixture"
print -- '/usr/bin/codesign --force --sign "$identity" --timestamp "$candidate_dmg"' >> "$mutation_fixture"
print -- 'mv "$publication_dir" "$final_dir"' >> "$mutation_fixture"
if mutation_output=$(zsh "$0" --check-order "$mutation_fixture" 2>&1); then
  print -u2 -- "Order checker accepted a fixture with DMG codesign below notarytool."
  exit 1
fi
if ! /usr/bin/grep -Fq 'must precede' <<<"$mutation_output"; then
  print -u2 -- "Order checker rejected the mutation for an unexpected reason."
  exit 1
fi

print -- "Release DMG signing workflow regression checks passed."
