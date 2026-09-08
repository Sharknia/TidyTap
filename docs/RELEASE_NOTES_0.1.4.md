# TidyTap 0.1.4

## 한국어

- 신규 설치에서 로그인 항목이 아직 등록되지 않았을 때 일반 기능 토글까지 적용에 실패하던 문제를 수정했습니다.
- 입력 기능 시작 실패 후 정상 복원된 비활성 헬퍼를 종료하고, 종료 직전 새 설정 요청을 놓치지 않도록 보완했습니다.
- 입력 연결 생성 실패와 실행 중 복구 실패를 구분하고, 중복 처리로 실패 결과가 지워지지 않도록 했습니다.
- 영어 README에 실제 영어 설정 화면을 추가하고 설치·사용 안내를 정리했습니다.

앱 자동 테스트 115개와 입력 엔진 테스트 101개를 통과했습니다. macOS 26.6.2 VM에서 최초 권한 승인 후 토글 적용, 입력 기능 네 가지 ON/OFF, 앱 재실행 시 설정 유지, 모두 OFF 후 헬퍼 종료를 확인했습니다. 물리 마우스·Caps Lock 전체 동작과 시간 경과에 따른 자연 회복을 모두 검증한 것은 아닙니다.

Apple Silicon 및 macOS 15.1 이상을 지원합니다. 이번 검증 환경은 macOS 26.5.2 및 26.6.2이며, 15.1 실제 실행 검증은 포함하지 않습니다.

## English

- Fixed feature toggles failing on a fresh installation when the login service was not yet registered.
- Improved helper shutdown after an input startup failure and protected new settings requests arriving during shutdown.
- Preserved distinct startup and recovery errors instead of allowing duplicate processing to erase a failure result.
- Added an English settings screenshot and clearer installation and usage guidance to the README.

Passed 115 app tests and 101 input-engine tests. A macOS 26.6.2 VM check covered toggles after the first permission grant, four input-feature switches, settings retention after reopening the app, and helper shutdown with all features off. This does not establish complete physical mouse/Caps Lock coverage or reproduce every time-dependent recovery scenario.

Requires Apple silicon and macOS 15.1 or later. Validation used macOS 26.5.2 and 26.6.2; macOS 15.1 runtime validation remains outstanding.
