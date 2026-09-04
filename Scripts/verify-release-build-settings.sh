#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

require_local=false
if (( $# > 0 )); then
  if [[ "$1" == "--require-local" && $# -eq 1 ]]; then
    require_local=true
  else
    print -u2 -- "Usage: ${0:t} [--require-local]"
    exit 2
  fi
fi

grep -q '^DEVELOPMENT_TEAM = $(TIDYTAP_DEVELOPMENT_TEAM)$' Config/Signing.xcconfig
grep -q '^CODE_SIGN_IDENTITY = $(TIDYTAP_DEVELOPER_ID_APPLICATION)$' Config/Signing.xcconfig
grep -q '^OTHER_CODE_SIGN_FLAGS = --timestamp$' Config/Signing.xcconfig

read_xcconfig_value() {
  local key="$1"
  local config_path="$2"
  /usr/bin/awk -v key="$key" '
    /^[[:space:]]*\/\// { next }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]*(//.*)?$", "")
      print
      exit
    }
  ' "$config_path"
}

if $require_local; then
  local_config="Config/LocalSigning.xcconfig"
  if [[ ! -f "$local_config" ]]; then
    print -u2 -- "Missing Config/LocalSigning.xcconfig."
    exit 2
  fi

  team_id=$(read_xcconfig_value TIDYTAP_DEVELOPMENT_TEAM "$local_config")
  identity=$(read_xcconfig_value TIDYTAP_DEVELOPER_ID_APPLICATION "$local_config")
  notary_profile=$(read_xcconfig_value TIDYTAP_NOTARYTOOL_KEYCHAIN_PROFILE "$local_config")
  if [[ ! "$team_id" =~ '^[A-Z0-9]{10}$' || -z "$identity" || -z "$notary_profile" ]]; then
    print -u2 -- "Local signing configuration has missing or invalid values."
    exit 2
  fi
fi

for target in TidyTap TidyTapHelper; do
  settings=$(xcodebuild -project TidyTap.xcodeproj -target "$target" -configuration Release -showBuildSettings)
  grep -q 'ENABLE_HARDENED_RUNTIME = YES' <<<"$settings"
  grep -q 'CODE_SIGN_STYLE = Manual' <<<"$settings"
  grep -q 'OTHER_CODE_SIGN_FLAGS = --timestamp' <<<"$settings"

  if $require_local; then
    grep -Fq "DEVELOPMENT_TEAM = $team_id" <<<"$settings"
    grep -Fq "CODE_SIGN_IDENTITY = $identity" <<<"$settings"
  fi
done

if $require_local; then
  echo "Release signing settings verified for TidyTap and TidyTapHelper with local values."
else
  echo "Release signing settings verified for TidyTap and TidyTapHelper."
fi
