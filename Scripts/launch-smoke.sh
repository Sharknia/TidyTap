#!/bin/zsh
# Build and launch isolated ad-hoc app/helper processes without touching the
# installed app, production preferences, login items, HID mappings, or taps.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

smoke_root=$(mktemp -d /tmp/tidytap-launch-smoke.XXXXXX)
derived_data="$smoke_root/DerivedData"
main_log="$smoke_root/main.log"
helper_log="$smoke_root/helper.log"
main_suite="com.sharknia.TidyTap.LaunchSmoke.Main.$$.${RANDOM}"
helper_suite="com.sharknia.TidyTap.LaunchSmoke.Helper.$$.${RANDOM}"
main_history_dir="$HOME/Library/Application Support/$main_suite/clipboard-history"
expired_history_entry="$main_history_dir/expired.clip"
recent_history_entry="$main_history_dir/recent.clip"
settings_content_width=560
settings_content_height=760
main_pid=""
duplicate_main_pid=""
helper_pid=""

cleanup() {
  if [[ -n "$main_pid" ]] && kill -0 "$main_pid" 2>/dev/null; then
    kill "$main_pid" 2>/dev/null || true
    wait "$main_pid" 2>/dev/null || true
  fi
  if [[ -n "$duplicate_main_pid" ]] && kill -0 "$duplicate_main_pid" 2>/dev/null; then
    kill "$duplicate_main_pid" 2>/dev/null || true
    wait "$duplicate_main_pid" 2>/dev/null || true
  fi
  if [[ -n "$helper_pid" ]] && kill -0 "$helper_pid" 2>/dev/null; then
    kill "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
  /usr/bin/defaults delete "$main_suite" >/dev/null 2>&1 || true
  /usr/bin/defaults delete "$helper_suite" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Application Support/$main_suite" "$HOME/Library/Application Support/$helper_suite"
  rm -rf "$smoke_root"
}
trap cleanup EXIT

# A prior interrupted run must not make the supposedly clean request non-default.
/usr/bin/defaults delete "$main_suite" >/dev/null 2>&1 || true
/usr/bin/defaults delete "$helper_suite" >/dev/null 2>&1 || true

snapshot_live_state() {
  {
    /usr/bin/hidutil property --get UserKeyMapping 2>&1 || print -- "unavailable"
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print "UserKeyMapping " $1 }'
  {
    /usr/bin/defaults export com.apple.symbolichotkeys - 2>&1 || print -- "unavailable"
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print "AppleSymbolicHotKeys " $1 }'
  {
    /usr/bin/defaults export com.sharknia.TidyTap - 2>&1 || print -- "unavailable"
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print "TidyTapPreferences " $1 }'
}

wait_for_log() {
  local process_id="$1"
  local log_path="$2"
  local pattern="$3"
  local attempts=0

  while (( attempts < 100 )); do
    if /usr/bin/grep -Fq "$pattern" "$log_path"; then
      return 0
    fi
    if ! kill -0 "$process_id" 2>/dev/null; then
      break
    fi
    sleep 0.1
    (( attempts += 1 ))
  done

  print -u2 -- "Process $process_id did not report '$pattern'."
  [[ ! -s "$log_path" ]] || /bin/cat "$log_path" >&2
  return 1
}

live_state_before=$(snapshot_live_state)

xcodebuild \
  -quiet \
  -project TidyTap.xcodeproj \
  -scheme TidyTap \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

app_path="$derived_data/Build/Products/Release/TidyTap.app"
helper_path="$app_path/Contents/MacOS/TidyTapHelper"
if [[ ! -d "$app_path" || ! -x "$helper_path" ]]; then
  print -u2 -- "Release build did not contain the app and embedded helper."
  exit 1
fi
"$project_root/Scripts/verify-macos-support.sh" "$app_path"

# Sign nested code first so the parent resource seal contains that signature.
"$project_root/Scripts/sign-sparkle-adhoc.sh" "$app_path" >/dev/null
/usr/bin/codesign --force --sign - --timestamp=none "$helper_path" >/dev/null
/usr/bin/codesign --force --sign - --timestamp=none "$app_path" >/dev/null
/usr/bin/codesign --verify --strict "$helper_path"
/usr/bin/codesign --verify --deep --strict "$app_path"

xcrun swiftc Scripts/verify-process-window.swift -o "$smoke_root/verify-process-window"

# The settings app should prune expired history even when the feature is off.
# Keep one valid recent item so this check cannot pass by deleting everything.
/usr/bin/python3 - "$main_history_dir" <<'PY'
import datetime
import os
import pathlib
import plistlib
import sys

directory = pathlib.Path(sys.argv[1])
directory.mkdir(parents=True, mode=0o700, exist_ok=True)
directory.chmod(0o700)
for name, copied_at in [
    ("expired.clip", datetime.datetime(1970, 1, 2, 3, 46, 40)),
    ("recent.clip", datetime.datetime.utcnow()),
]:
    entry = {
        "id": "00000000-0000-0000-0000-000000000001" if name == "expired.clip"
            else "00000000-0000-0000-0000-000000000002",
        "copiedAt": copied_at,
        "content": {"text": {"plain": name}},
    }
    path = directory / name
    path.write_bytes(plistlib.dumps(entry, fmt=plistlib.FMT_BINARY))
    path.chmod(0o600)
PY

env \
  TIDYTAP_LAUNCH_SMOKE=1 \
  TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$main_suite" \
  "$app_path/Contents/MacOS/TidyTap" >"$main_log" 2>&1 &
main_pid=$!

wait_for_log "$main_pid" "$main_log" "TIDYTAP_LAUNCH_SMOKE main-delegate-started"
if [[ -e "$expired_history_entry" || ! -e "$recent_history_entry" ]]; then
  print -u2 -- "Settings startup did not prune only expired clipboard history."
  exit 1
fi
window_verified=0
for attempt in {1..20}; do
  if "$smoke_root/verify-process-window" "$main_pid" "$settings_content_width" "$settings_content_height" \
      >"$smoke_root/window-check.log" 2>&1; then
    window_verified=1
    break
  fi
  sleep 0.1
done
cat "$smoke_root/window-check.log"
if (( window_verified == 0 )); then
  tail -10 "$main_log" >&2
  print -u2 -- "Settings window did not settle at its requested size."
  exit 1
fi
/usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE main-helper-launch-skipped" "$main_log"
/usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE main-login-item-mutation-skipped" "$main_log"

env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$main_suite" \
  "$app_path/Contents/MacOS/TidyTap" >"$smoke_root/duplicate-main.log" 2>&1 &
duplicate_main_pid=$!
for attempt in {1..20}; do
  kill -0 "$duplicate_main_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$duplicate_main_pid" 2>/dev/null || ! kill -0 "$main_pid" 2>/dev/null; then
  print -u2 -- "A second settings process stayed running or displaced the first."
  exit 1
fi
wait "$duplicate_main_pid"
duplicate_main_pid=""

kill "$main_pid"
wait "$main_pid" 2>/dev/null || true
main_pid=""

env \
  TIDYTAP_LAUNCH_SMOKE=1 \
  TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$helper_log" 2>&1 &
helper_pid=$!

wait_for_log "$helper_pid" "$helper_log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
attempts=0
while kill -0 "$helper_pid" 2>/dev/null && (( attempts < 100 )); do
  sleep 0.1
  (( attempts += 1 ))
done
if kill -0 "$helper_pid" 2>/dev/null; then
  print -u2 -- "All-off helper did not terminate."
  exit 1
fi
wait "$helper_pid"
helper_pid=""

/usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE helper-caps-disabled" "$helper_log"
/usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE helper-input-wheel-off-buttons-off" "$helper_log"
/usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE helper-menu-hidden" "$helper_log"
if /usr/bin/grep -Eq "helper-caps-enabled|helper-input-wheel-on|helper-input-.*buttons-on|helper-menu-visible" "$helper_log"; then
  print -u2 -- "Helper smoke unexpectedly requested a live feature."
  exit 1
fi

# Keep a fake Caps feature active: this exercises the real worker lifetime and
# lock while the smoke adapters guarantee there are no HID or event-tap changes.
xcrun swift -e '
import Foundation
let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
let request: [String: Any] = ["applyRequestID": UUID().uuidString, "settings": [
    "capsLockInputSourceSwitching": true, "reverseMouseWheelVertically": false,
    "sideButtonNavigation": false, "launchAtLogin": false
]]
defaults.set(try JSONSerialization.data(withJSONObject: request), forKey: "settings")
defaults.synchronize()
' "$helper_suite"

env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/active.log" 2>&1 &
helper_pid=$!
wait_for_log "$helper_pid" "$smoke_root/active.log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/duplicate.log" 2>&1
if /usr/bin/grep -Fq "helper-delegate-started" "$smoke_root/duplicate.log"; then
  print -u2 -- "Duplicate worker started a second input lifecycle."
  exit 1
fi
kill -0 "$helper_pid"
kill "$helper_pid"
wait "$helper_pid" 2>/dev/null || true
helper_pid=""

# A stopped/crashed process must release the lock without clearing a PID file.
env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/restarted.log" 2>&1 &
helper_pid=$!
wait_for_log "$helper_pid" "$smoke_root/restarted.log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
kill "$helper_pid"
wait "$helper_pid" 2>/dev/null || true
helper_pid=""

# A fixed-step-only snapshot must keep the fake-input worker alive even when
# reversal, Caps Lock and side buttons are all off. Use no shared notifications:
# an installed production worker could also observe their application object.
xcrun swift -e '
import Foundation
let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
let request: [String: Any] = ["applyRequestID": UUID().uuidString, "settings": [
    "capsLockInputSourceSwitching": false, "reverseMouseWheelVertically": false,
    "sideButtonNavigation": false, "launchAtLogin": false,
    "fixedMouseWheelStepEnabled": true, "mouseWheelStepLines": 7
]]
defaults.set(try JSONSerialization.data(withJSONObject: request), forKey: "settings")
defaults.synchronize()
' "$helper_suite"

env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/fixed-step.log" 2>&1 &
helper_pid=$!
wait_for_log "$helper_pid" "$smoke_root/fixed-step.log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
kill -0 "$helper_pid"
kill "$helper_pid"
wait "$helper_pid" 2>/dev/null || true
helper_pid=""

# Verify the effective result and disable just this feature, preserving its
# remembered size. A fresh worker must apply all-off and terminate normally.
xcrun swift -e '
import Foundation
let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
defaults.synchronize()
guard let statusData = defaults.data(forKey: "applyStatus"),
      let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
      status["outcome"] as? String == "applied",
      let effective = status["effectiveSettings"] as? [String: Any],
      effective["fixedMouseWheelStepEnabled"] as? Bool == true,
      effective["mouseWheelStepLines"] as? Int == 7,
      effective["reverseMouseWheelVertically"] as? Bool == false else {
    fatalError("Fixed-step-only effective settings were not applied")
}
var disabled = effective
disabled["fixedMouseWheelStepEnabled"] = false
let request: [String: Any] = ["applyRequestID": UUID().uuidString, "settings": disabled]
defaults.set(try JSONSerialization.data(withJSONObject: request), forKey: "settings")
defaults.synchronize()
' "$helper_suite"

env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/fixed-step-off.log" 2>&1 &
helper_pid=$!
wait_for_log "$helper_pid" "$smoke_root/fixed-step-off.log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
attempts=0
while kill -0 "$helper_pid" 2>/dev/null && (( attempts < 100 )); do
  sleep 0.1
  (( attempts += 1 ))
done
if kill -0 "$helper_pid" 2>/dev/null; then
  print -u2 -- "Worker did not exit after fixed-step-only was disabled."
  exit 1
fi
wait "$helper_pid"
helper_pid=""

xcrun swift -e '
import Foundation
let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
defaults.synchronize()
guard let data = defaults.data(forKey: "applyStatus"),
      let status = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      status["outcome"] as? String == "applied",
      let effective = status["effectiveSettings"] as? [String: Any],
      effective["fixedMouseWheelStepEnabled"] as? Bool == false,
      effective["mouseWheelStepLines"] as? Int == 7 else {
    fatalError("Disabled fixed-step size was not preserved")
}
' "$helper_suite"

# An update must stop its matching worker gracefully and release worker.lock.
# The test notification uses the isolated suite, so the installed worker never sees it.
xcrun swift -e '
import Foundation
let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
let request: [String: Any] = ["applyRequestID": UUID().uuidString, "settings": [
    "capsLockInputSourceSwitching": true, "reverseMouseWheelVertically": false,
    "sideButtonNavigation": false, "launchAtLogin": false
]]
defaults.set(try JSONSerialization.data(withJSONObject: request), forKey: "settings")
defaults.synchronize()
' "$helper_suite"
env TIDYTAP_UPDATE_STOP_PROBE=1 TIDYTAP_LAUNCH_SMOKE=1 \
  TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$helper_suite" \
  "$helper_path" >"$smoke_root/update-stop.log" 2>&1 &
helper_pid=$!
wait_for_log "$helper_pid" "$smoke_root/update-stop.log" "TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
xcrun swift -e '
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.sharknia.TidyTap.prepareForUpdate"),
    object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true
)
' "$helper_suite"
attempts=0
while kill -0 "$helper_pid" 2>/dev/null && (( attempts < 100 )); do
  sleep 0.1
  (( attempts += 1 ))
done
if kill -0 "$helper_pid" 2>/dev/null; then
  print -u2 -- "Worker did not stop for an update."
  exit 1
fi
wait "$helper_pid"
helper_pid=""

live_state_after=$(snapshot_live_state)
if [[ "$live_state_before" != "$live_state_after" ]]; then
  print -u2 -- "Live HID, symbolic-hotkey, or production preference state changed during smoke."
  print -u2 -- "Before (hashes only): $live_state_before"
  print -u2 -- "After (hashes only): $live_state_after"
  exit 1
fi

print -- "Launch smoke passed: settings window, expired clipboard pruning, duplicate-app and duplicate-worker exclusion, graceful update stop, all-off exit, restart after exit, fixed-step-only lifecycle, and no live state mutation."
