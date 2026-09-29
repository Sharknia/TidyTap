# TidyTap 0.2.2

## 한국어

- 클립보드 히스토리에서 항목을 고른 뒤 원래 입력칸의 접근성 값이 잠깐 비어 붙여넣기가 중단되던 문제를 수정했습니다. 원래 입력칸이 다시 확인될 때만 최대 약 150ms 동안 재확인합니다. 다른 앱이나 입력칸으로 바뀌면 붙여넣지 않습니다.
- 새 호출이 진행 중인 재확인을 대체하면 이전 항목이 뒤늦게 붙거나 오류창이 뜨지 않도록 했습니다.
- 사용자 전용 진단 로그를 추가했습니다. 검색어와 선택한 텍스트의 앞부분, 길이, 해시 등이 기록될 수 있으며 두 로그 파일의 합계는 최대 256KiB입니다. 7일 지난 기록은 다음 사용 시 정리하고, 히스토리 항목 삭제 시 로그도 지웁니다. 자세한 내용은 [문제 해결](TROUBLESHOOTING.ko.md)을 참고하세요.

macOS 26.6.2에서 앱 테스트 160개와 입력 엔진 테스트 119개, 격리 Helper 시작 검사가 통과했습니다. Developer ID 서명과 Apple 공증을 받은 0.2.2 후보의 실제 입력칸 삽입 검증은 [수용 현황](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md)에 별도로 기록합니다.

Apple Silicon 및 macOS 15.1 이상을 대상으로 합니다.

## English

- Fixed clipboard history paste stopping when the original input field briefly has no Accessibility value after the picker closes. TidyTap retries for up to about 150 ms and pastes only when the original field is confirmed. It stops if the app or field changes.
- A new invocation cancels an older pending retry so the older item cannot paste late or show a stale error.
- Added a private diagnostic log that may include short previews of the search term and selected text, their lengths, and hashes. The current and previous log files together are limited to 256 KiB. Entries older than seven days are removed on the next use, and deleting a history item clears the log. See [Troubleshooting](TROUBLESHOOTING.md).

Passed 160 app tests, 119 input-engine tests, and isolated Helper startup on macOS 26.6.2. Direct insertion checks for a Developer ID-signed and Apple-notarized 0.2.2 candidate are tracked separately in the [acceptance status](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md).

Targets Apple silicon and macOS 15.1 or later.
