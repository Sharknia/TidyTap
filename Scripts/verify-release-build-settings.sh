#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

grep -q '^DEVELOPMENT_TEAM = $(TIDYTAP_DEVELOPMENT_TEAM)$' Config/Signing.xcconfig
grep -q '^CODE_SIGN_IDENTITY = $(TIDYTAP_DEVELOPER_ID_APPLICATION)$' Config/Signing.xcconfig

for target in TidyTap TidyTapHelper; do
  settings=$(xcodebuild -project TidyTap.xcodeproj -target "$target" -configuration Release -showBuildSettings)
  grep -q 'ENABLE_HARDENED_RUNTIME = YES' <<<"$settings"
  grep -q 'CODE_SIGN_STYLE = Manual' <<<"$settings"
done

echo "Release signing settings verified for TidyTap and TidyTapHelper."
