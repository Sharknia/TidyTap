# TidyTap 0.1.3

## 한국어

- Finder에서 파일 목록의 `⌘X → ⌘V` 이동과 일반 `⌘C → ⌘V` 복사를 지원합니다. 네 보기(목록·아이콘·계층·갤러리)에서 전역 키 동작을 확인했습니다.
- 선택 항목 옆에 ‘이동 준비됨’ 또는 ‘복사 준비됨’을 약 1초간 표시합니다. 표시 중 Finder의 전면 상태와 키 입력을 유지합니다.
- 설정 적용 중 스위치의 완료 응답과 비활성화 순서를 보완했습니다.
- Apple Silicon 및 macOS 15.1 이상을 대상으로 빌드합니다. 검증 실행 OS는 macOS 26.5.2이며, macOS 15.1 실제 실행은 아직 검증하지 않았습니다.

검증: Finder 이동·복사, 이름 변경 중 원래 편집 동작, 선택 항목 옆 패널 표시, 연속 알림, 설정 앱 재연결, 관련 앱·엔진 테스트와 독립 리뷰를 확인했습니다. 사용자가 Finder 기능의 실제 사용을 확인했습니다. 최종 엔진 테스트 101개, 앱 테스트 104개, 릴리스 launch-smoke의 시스템 상태 미변경 검사와 DMG 워크플로 검사가 통과했습니다.

## English

- Added Finder file moves with `⌘X → ⌘V` while keeping ordinary `⌘C → ⌘V` as copy. Global-key behavior was checked in list, icon, column, and gallery views.
- Shows “Move ready” or “Copy ready” beside the selected item for about one second while Finder keeps focus and input.
- Improved the settings switch completion and disable ordering while applying settings.
- Builds for Apple silicon Macs running macOS 15.1 or later. Validation ran on macOS 26.5.2; runtime validation on macOS 15.1 remains outstanding.

Validation covered Finder move and copy, normal editing during rename, the selected-item panel, repeated notifications, settings-app reconnection, related app and engine tests, and an independent review. The user confirmed the Finder feature in actual use. Final validation passed 101 engine tests, 104 app tests, the launch-smoke system-state preservation check, and the DMG workflow checks.
