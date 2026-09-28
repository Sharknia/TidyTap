# TidyTap 0.2.1

## 한국어

- 클립보드 단축키가 TidyTap을 먼저 실행한 뒤 설정 화면을 열면 **업데이트 확인** 버튼이 비활성화되던 문제를 수정했습니다. 설정 화면을 시작할 때 Sparkle을 한 번만 초기화해 자동 확인과 수동 버튼을 사용할 수 있습니다.
- 0.2.0의 클립보드 기록·붙여넣기와 기존 입력 기능 동작은 변경하지 않았습니다.

앱 테스트 144개, 입력 엔진 테스트 119개, 격리 실행 검사가 macOS 26.5.2에서 통과했습니다. 0.2.0에서는 앱 안에서 0.1.4 프리뷰를 다운로드·교체·재실행하고 설정과 Helper가 유지되는 것을 실제 확인했습니다. 0.2.1의 최종 업데이트 경로는 공개 피드가 게시된 뒤 별도로 검증합니다.

Apple Silicon 및 macOS 15.1 이상을 대상으로 합니다.

## English

- Fixed **Check for Updates** being disabled when the clipboard shortcut launched TidyTap before Settings opened. Sparkle now starts once when a settings session begins, making automatic checks and the manual button available on that path.
- Clipboard history, paste behavior, and existing input features from 0.2.0 are unchanged.

Passed 144 app tests, 119 input-engine tests, and isolated launch smoke on macOS 26.5.2. The 0.1.4 preview was updated through the app to 0.2.0 with settings and Helper preserved. The final 0.2.1 update path still needs verification after its public feed is published.

Targets Apple silicon and macOS 15.1 or later.
