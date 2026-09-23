#!/bin/zsh
# Isolated G1/G2 manual test or bounded G3 live-copy monitor. G1/G2 does not
# read the user's existing clipboard. G3 may probe it once for permission,
# then saves new copies; logs contain metadata only.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--startup-only" && "$1" != "--g2-media" && "$1" != "--g3-live" && "$1" != "--settings-integration" && "$1" != "--settings-denied" ]]; }; then
  print -u2 -- "Usage: ${0:t} [--startup-only|--g2-media|--g3-live|--settings-integration|--settings-denied]"
  exit 2
fi

probe_root=$(mktemp -d /tmp/tidytap-clipboard-gates.XXXXXX)
suite="com.sharknia.TidyTap.LaunchSmoke.ClipboardGates.$$.${RANDOM}"
app_path="$probe_root/DerivedData/Build/Products/Debug/TidyTap.app"
helper_path="$app_path/Contents/MacOS/TidyTapHelper"
helper_log="$probe_root/helper.log"
app_log="$probe_root/app.log"
helper_pid=""

cleanup() {
  if [[ -n "$helper_pid" ]] && kill -0 "$helper_pid" 2>/dev/null; then
    kill "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
  if [[ -x "$app_path/Contents/MacOS/TidyTap" ]]; then
    local actual_app=$(/bin/realpath "$app_path/Contents/MacOS/TidyTap")
    local process_id command_path
    while read -r process_id command_path; do
      if [[ "$command_path" == "$actual_app" || "$command_path" == "$app_path/Contents/MacOS/TidyTap" ]]; then
        kill "$process_id" 2>/dev/null || true
      fi
    done < <(ps -axo pid=,command=)
  fi
  /usr/bin/defaults delete "$suite" >/dev/null 2>&1 || true
  rm -rf "${HOME}/Library/Application Support/$suite" "$probe_root"
}
trap cleanup EXIT INT TERM
: > "$app_log"
/bin/chmod 600 "$app_log"

xcodebuild -quiet -project TidyTap.xcodeproj -scheme TidyTap \
  -configuration Debug -derivedDataPath "$probe_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build
/usr/bin/codesign --force --sign - --timestamp=none "$helper_path" >/dev/null
/usr/bin/codesign --force --sign - --timestamp=none "$app_path" >/dev/null
/usr/bin/codesign --verify --deep --strict "$app_path"

if [[ "${1:-}" == "--g3-live" ]]; then
  env TIDYTAP_CLIPBOARD_G3_PROBE=1 TIDYTAP_LAUNCH_SMOKE=1 \
    TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$suite" \
    "$helper_path" >"$helper_log" 2>&1 &
elif [[ "${1:-}" == "--settings-integration" || "${1:-}" == "--settings-denied" ]]; then
  deny="0"
  [[ "${1:-}" != "--settings-denied" ]] || deny="1"
  env TIDYTAP_CLIPBOARD_SETTINGS_PROBE=1 TIDYTAP_CLIPBOARD_SETTINGS_PROBE_DENY="$deny" TIDYTAP_LAUNCH_SMOKE=1 \
    TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$suite" \
    "$helper_path" >"$helper_log" 2>&1 &
else
  media_probe="0"
  [[ "${1:-}" != "--g2-media" ]] || media_probe="1"
  env TIDYTAP_CLIPBOARD_G1_PROBE=1 TIDYTAP_CLIPBOARD_G2_MEDIA_PROBE="$media_probe" \
    TIDYTAP_CLIPBOARD_G1_LOG_PATH="$app_log" TIDYTAP_LAUNCH_SMOKE=1 \
    TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$suite" \
    "$helper_path" >"$helper_log" 2>&1 &
fi
helper_pid=$!

ready_marker="clipboard-g1: shortcut tap active"
[[ "${1:-}" != "--g3-live" ]] || ready_marker="clipboard-g3: monitor active"
[[ "${1:-}" != "--settings-integration" && "${1:-}" != "--settings-denied" ]] || ready_marker="TIDYTAP_LAUNCH_SMOKE helper-delegate-started"
ready=false
for attempt in {1..50}; do
  if /usr/bin/grep -Fq "$ready_marker" "$helper_log"; then
    ready=true
    break
  fi
  if ! kill -0 "$helper_pid" 2>/dev/null; then break; fi
  sleep 0.1
done
if ! $ready; then
  print -u2 -- "격리 Helper의 단축키 탭이 시작되지 않았습니다."
  [[ ! -s "$helper_log" ]] || /bin/cat "$helper_log" >&2
  exit 1
fi
print -- "격리 Helper 준비 완료."
/usr/bin/grep -F "$ready_marker" "$helper_log"

if [[ "${1:-}" == "--settings-integration" || "${1:-}" == "--settings-denied" ]]; then
  env TIDYTAP_LAUNCH_SMOKE=1 TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$suite" \
    "$app_path/Contents/MacOS/TidyTap" >"$app_log" 2>&1 &
  app_ready=false
  for attempt in {1..50}; do
    if /usr/bin/grep -Fq "TIDYTAP_LAUNCH_SMOKE main-delegate-started" "$app_log"; then
      app_ready=true
      break
    fi
    sleep 0.1
  done
  if ! $app_ready; then
    print -u2 -- "격리 설정 앱이 시작되지 않았습니다."
    [[ ! -s "$app_log" ]] || /bin/cat "$app_log" >&2
    exit 1
  fi
  print -- "격리 설정 앱: $app_path"
  print -- "180초 동안 설정 화면의 클립보드 스위치를 시험합니다. 설치 앱 설정은 변경하지 않습니다."
  [[ "${1:-}" != "--settings-denied" ]] || print -- "이 시험의 클립보드 읽기 상태만 거부로 주입합니다."
  read -r -t 180 _ || true
  /usr/bin/grep -F "TIDYTAP_LAUNCH_SMOKE" "$app_log" || true
  print -- "설정 통합 시험을 종료합니다."
  exit 0
fi

if [[ "${1:-}" == "--g3-live" ]]; then
  g3_seconds="${TIDYTAP_G3_SECONDS:-120}"
  if [[ ! "$g3_seconds" =~ '^[0-9]+$' ]] || (( g3_seconds < 1 || g3_seconds > 120 )); then
    print -u2 -- "TIDYTAP_G3_SECONDS는 1~120초여야 합니다."
    exit 2
  fi
  print -- "${g3_seconds}초 동안 새 복사를 감시합니다. 복사 내용은 출력하지 않습니다."
  print -- "⌥C로 히스토리 창을 열 수 있습니다. Esc나 ⌥C로 닫으면 클립보드는 바뀌지 않습니다."
  /bin/sleep "$g3_seconds"
  kill "$helper_pid"
  wait "$helper_pid" 2>/dev/null || true
  helper_pid=""
  env TIDYTAP_CLIPBOARD_G3_PROBE=1 TIDYTAP_LAUNCH_SMOKE=1 \
    TIDYTAP_LAUNCH_SMOKE_PREFERENCES_SUITE="$suite" \
    "$helper_path" >>"$helper_log" 2>&1 &
  helper_pid=$!
  for attempt in {1..50}; do
    if [[ $(/usr/bin/grep -Fc "$ready_marker" "$helper_log") -ge 2 ]]; then break; fi
    if ! kill -0 "$helper_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if [[ $(/usr/bin/grep -Fc "$ready_marker" "$helper_log") -lt 2 ]]; then
    print -u2 -- "격리 Helper 재시작에 실패했습니다."
    /bin/cat "$helper_log" >&2
    exit 1
  fi
  /usr/bin/grep -F "clipboard-g3:" "$helper_log" || true
  capture_count=$(/usr/bin/grep -Fc "clipboard-g3: captured #" "$helper_log" || true)
  persisted_count=$(/usr/bin/grep -F "clipboard-g3: existing entries=" "$helper_log" | /usr/bin/tail -1 | /usr/bin/sed 's/.*=//')
  if (( capture_count > 0 && persisted_count > 0 )); then
    print -- "새 복사 ${capture_count}건과 Helper 재시작 후 기록 ${persisted_count}건을 확인했습니다."
  else
    print -- "시험 중 새 복사가 없어 재시작 후 기록 유지 여부는 확인하지 못했습니다."
  fi
  print -- "실사용 복사 감시 시험을 종료합니다."
  exit 0
fi

if [[ "${1:-}" == "--g2-media" ]]; then
  if ! /usr/bin/grep -Fq "clipboard-g1: prepared entries=3" "$helper_log"; then
    print -u2 -- "격리 Helper가 이미지·서식 시험 기록 3건을 준비하지 못했습니다."
    /bin/cat "$helper_log" >&2
    exit 1
  fi
  print -- "시험 기록: 맨 위 48x48 주황·파랑 이미지, 두 번째 빨간 굵은 글씨, 세 번째 일반 텍스트."
  print -- "TextEdit 리치 텍스트 문서에서 ⌥C→Enter는 이미지, 다시 ⌥C→↓→⇧Enter는 서식 포함, 다시 ⌥C→↓→Enter는 서식 없이 붙여넣습니다."
  print -- "붙여넣기는 현재 시스템 클립보드를 해당 시험 항목으로 바꿉니다. 시험 종료는 이 터미널에서 Enter, 또는 240초 뒤 자동 정리입니다."
  read -r -t 240 _ || true
  [[ ! -s "$app_log" ]] || /bin/cat "$app_log"
  print -- "이미지·서식 실사용 시험을 종료합니다."
  exit 0
fi

print -- "시험 기록: TidyTap G2 test text"

if [[ "${1:-}" == "--startup-only" ]]; then
  print -- "시작 확인만 완료했습니다. 시험 프로세스를 정리합니다."
  exit 0
fi

print -- "TextEdit의 빈 문서에서 ⌥C를 누르세요. 히스토리 창이 열리면 Enter로 시험 문구를 붙여넣으세요."
print -- "Enter를 누르면 현재 시스템 클립보드는 시험 문구로 바뀝니다. 취소하려면 Esc를 누르세요."
print -- "결과를 확인한 뒤 이 터미널에 Enter를 누르세요. 120초 후 자동 정리합니다."
read -r -t 120 _ || true
[[ ! -s "$app_log" ]] || /bin/cat "$app_log"
print -- "시험을 종료합니다."
