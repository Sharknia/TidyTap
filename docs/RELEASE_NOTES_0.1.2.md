# TidyTap 0.1.2

## 한국어

- 손쉬운 사용으로 충족되는 이벤트 접근을 별도 입력 모니터링 승인으로 표시하던 문제를 수정했습니다. 불필요한 입력 모니터링 설정 버튼과 이전 버전의 미응답 권한 요청 재실행을 제거했습니다.
- 새 환경에서 키 매핑이 없을 때 Caps Lock 설정 적용이 실패하던 `(null)` 파싱 문제를 수정했습니다.
- Caps Lock 설정 실패와 복원 필요 상태를 한국어·영어로 구분해 안내합니다. 다른 기능의 실패 뒤 Caps Lock 복원까지 실패하는 경우도 포함합니다.
- DMG 생성 중 서명된 앱에 Finder 메타데이터가 추가되어 엄격한 서명 검증에 실패하던 문제를 수정했습니다.

검증: 앱 테스트 97개, 입력 엔진 테스트 82개와 격리된 프로세스 검증을 통과했습니다. 현재 Mac에서 업데이트 후 권한 재승인 없이 실행, Caps Lock 설정 적용·비활성화 복원, 입력 모니터링 목록 제거 후 새 Worker의 마우스 설정 적용을 확인했습니다. 사용자가 마우스 정상 동작을 확인했습니다.

알려진 제한: VIA 등으로 이미 F19 한·영 전환을 구성한 키보드에서는 Caps Lock 기능을 꺼두세요. 이 기능은 실제 Caps Lock 입력과 macOS 단축키를 F18로 연결하며 기존 커스텀 단축키를 자동 재사용하지 않습니다. 재매핑되지 않은 물리 Caps Lock 전환, 새 계정의 최초 승인, 실제 재로그인·재부팅은 별도 인수 검증이 남아 있습니다.

## English

- Corrected permission guidance: event access provided by Accessibility is no longer shown as a separate Input Monitoring grant. Removed the redundant settings button and replay of unanswered legacy Input Monitoring requests.
- Fixed Caps Lock setup failing on an unconfigured keyboard mapping when `hidutil` returns `(null)`.
- Added specific Korean and English Caps Lock failure and recovery messages, including rollback failures following an error in another feature.
- Prevented the DMG layout from adding Finder metadata to a signed app and breaking strict signature verification.

Validation includes 97 app tests, 82 input-engine tests, isolated process checks, and a local update retaining access without reauthorization. Live Caps Lock configuration and restoration were verified, along with mouse configuration after removing the Input Monitoring entry and restarting the worker. The user confirmed mouse operation.

Known limits: leave the Caps Lock feature off if a keyboard already uses a custom F19 input-source binding through VIA or similar tools. TidyTap maps actual Caps Lock input and the macOS shortcut to F18; it does not reuse custom shortcuts. Physical switching with an unmodified Caps Lock key, first approval on a fresh account, and real login/reboot acceptance remain separate checks.
