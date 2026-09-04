#!/bin/zsh
# Confirm a DMG checksum sidecar is portable: it names only the DMG basename.
set -euo pipefail

if (( $# != 1 )); then
  print -u2 -- "Usage: ${0:t} path/to/package.dmg"
  exit 2
fi

dmg_path="$1"
sidecar_path="$dmg_path.sha256"
if [[ ! -f "$dmg_path" || ! -f "$sidecar_path" ]]; then
  print -u2 -- "Both the DMG and its .sha256 sidecar are required."
  exit 1
fi

dmg_name="${dmg_path:t}"
expected_line=$(cd "${dmg_path:h}" && /usr/bin/shasum -a 256 "$dmg_name")
actual_line=$(<"$sidecar_path")
if [[ "$actual_line" != "$expected_line" || "$actual_line" == *"/"* ]]; then
  print -u2 -- "The checksum sidecar must contain the matching DMG basename only."
  exit 1
fi

copy_dir=$(mktemp -d "${TMPDIR:-/tmp}/TidyTap-sidecar.XXXXXX")
trap 'rm -rf "$copy_dir"' EXIT
/usr/bin/ditto "$dmg_path" "$copy_dir/$dmg_name"
/usr/bin/ditto "$sidecar_path" "$copy_dir/${dmg_name}.sha256"
(
  cd "$copy_dir"
  /usr/bin/shasum -a 256 -c "${dmg_name}.sha256" >/dev/null
)

print -- "DMG checksum sidecar is portable."
