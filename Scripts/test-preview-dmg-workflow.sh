#!/bin/zsh
# Static regression checks for preview packaging. This never builds, signs,
# mounts, installs, notarizes, or publishes an artifact.
set -euo pipefail

project_root="${0:A:h:h}"
preview_script="$project_root/Scripts/package-preview-dmg.sh"

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

# The argument parser fails before it can build when the explicit value is
# missing; this is a no-side-effect CLI regression check.
if zsh "$preview_script" --developer-id-config >/dev/null 2>&1; then
  print -u2 -- "Developer ID preview accepted a missing config path."
  exit 1
fi

print -- "Preview DMG workflow regression checks passed."
