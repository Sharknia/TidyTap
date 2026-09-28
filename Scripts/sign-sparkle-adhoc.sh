#!/bin/zsh
# An unsigned Xcode build embeds pre-signed Sparkle binaries. Sign nested code
# before the framework and parent app for an isolated ad-hoc preview.
set -euo pipefail

if (( $# != 1 )); then
  print -u2 -- "Usage: ${0:t} /path/to/TidyTap.app"
  exit 2
fi

framework="$1/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$framework" ]]; then
  print -u2 -- "Sparkle.framework is missing from the app."
  exit 1
fi

for component in \
  "$framework/Versions/B/Autoupdate" \
  "$framework/Versions/B/Updater.app" \
  "$framework/Versions/B/XPCServices/Downloader.xpc" \
  "$framework/Versions/B/XPCServices/Installer.xpc"; do
  /usr/bin/codesign --force --sign - --timestamp=none "$component"
done
/usr/bin/codesign --force --sign - --timestamp=none "$framework"
