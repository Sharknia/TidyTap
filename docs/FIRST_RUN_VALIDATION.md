# 최초 설치 수정 검증 기록

작성일: 2026-09-07  
브랜치: `fix/first-run-permissions-capslock`  
상태: 구현·독립 리뷰·자동 검증 및 현재 Mac 업데이트 검증 완료, 최초 승인·물리 Caps Lock 인수 항목 잔여

## 기준과 분담

`origin/dev`의 `b414f80`에서 분기한 뒤 `v0.1.1`을 병합했다. 0.1.1의 고정 휠 단계, Worker 교체 및 DMG 설치 구성을 보존한다. 계획서는 `4ca04f2`로 커밋하고 원격에 푸시했다.

루나는 최소 설계 점검, 테라는 HID 파서 및 별도 오류 메시지 구현, 솔은 권한 UI/상태 흐름을 맡았다. 구현별 검토는 구현자 대화 없이 새 솔에게 diff를 전달한다. 오케스트레이터가 범위·통합·서명·테스트 결과를 확인한다.

## 확인된 결과

- HID 파서 변경: `477d620` (위임 작업 원본 `df02cb6`). 패키지 테스트 82개, 실패 0개.
- 실제 환경: macOS 26.5.2 (`25F84`), 활성 입력 소스 2개, `hidutil` 매핑 출력 `(null)`.
- 실제 제품 소스를 컴파일한 읽기 전용 진단에서 `(null)`은 빈 매핑으로 처리되고 `CapsLockFeatureController.prepareEnablePlan()`이 통과했다. 수정 전 같은 경로는 `invalidSystemData(hidMappings)`로 실패했다.
- `InputSourceShortcutController.prepareEnable()`도 통과했다. 기존 단축키를 읽고 변경안을 만들었으며 실제 쓰기·활성화·복원은 수행하지 않았다.
- `Scripts/verify-release-build-settings.sh` 통과: 앱과 Helper의 수동 Release 서명·hardened runtime·타임스탬프 설정 확인.
- 오류 메시지 변환은 `249125e`, 매핑 충돌 문구 정정은 `ecabc7f`, 권한 UI는 `db5f49c`, 오류 화면 연결은 `0717c77`로 통합했다.
- 통합 앱 테스트 96개 통과, 실패·건너뜀 0개. 결과: `build/first-run-tests/Logs/Test/Test-TidyTap-2026.09.07_10-30-54-+0900.xcresult`. 최초 통합 테스트의 pending 상태 생성자 인수 누락을 수정한 뒤 통과했다.
- `Scripts/launch-smoke.sh` 통과: 560×760 설정 창, all-off 종료, 중복 Worker 차단, Worker 재시작, 고정 단계 단독 활성 수명, 기존 HID·단축키·운영 preferences 해시 유지.
- AppKit 오프스크린 렌더링에서 한국어 읽기 실패·영어 매핑 충돌·손쉬운 사용 미승인·영어 다크 모드 화면을 확인했다. 별도 입력 모니터링 행이 없고 오류 문구와 하단 정보가 보인다. 이는 실제 TCC 승인 화면 검증이 아니다.
- HID 변경과 오류 메시지 변경은 각각 새 솔의 독립 리뷰에서 실제 결함 없음. 권한 후속 수정과 DMG 수정도 각각 새 솔의 독립 리뷰에서 실제 결함 없음.
- 사용자 요청으로 `origin/dev`를 `ad5eb3a`까지 fast-forward했다. PR #16·#17의 병합 대상은 `main`이었다. 현재 `origin/dev`, `origin/main`, `v0.1.1`이 같은 기준을 사용한다.
- 권한 독립 리뷰에서 과거 미응답 `.request(.inputMonitoring)`이 업데이트 시 재실행될 수 있음을 발견했다. `769858c`에서 해당 요청을 읽기 전용 응답으로 처리하도록 수정하고 startup·재처리 회귀 테스트를 갱신했다. 손쉬운 사용 요청은 유지한다.
- 최종 코드 `769858c`의 앱 테스트도 96개 통과, 실패·건너뜀 0개다. 결과: `build/first-run-tests/Logs/Test/Test-TidyTap-2026.09.07_10-37-30-+0900.xcresult`. 후속 launch smoke도 같은 비변경·프로세스 조건으로 통과했다.
- 오류 문구 독립 리뷰 중 기존 `HelperLauncherTests.testDynamicIdentityDetectsReplacementWhenAdHocDesignatedRequirementChanges`의 종료 후 프로세스 개수 assertion이 한 번 실패했다. 리뷰어의 단독 재실행과 두 번의 통합 전체 실행에서는 통과했다. 이번 변경의 회귀로 확정하지 않았고, 해당 기존 테스트는 수정하지 않았다.
- 최종 통합 솔 리뷰에서 뒤 단계 실패 후 Caps Lock rollback 실패의 복원 안내 누락을 발견했다. `7a55f95`에서 `lifecycle.rollbackFailed`의 정확한 `capsLock` 토큰을 판별하도록 보완했다. 새 솔의 후속 독립 리뷰에서 결함 없음, 관련 테스트 8개 통과.
- 최종 앱 테스트 97개 통과, 실패·건너뜀 0개. 보존한 결과: `build/validation/app-tests-7a55f95.xcresult`. 입력 엔진은 이후 변경 없이 앞서 검증한 82개 테스트 통과 상태다.

## 서명 프리뷰

첫 실제 패키징은 DMG 복사 앱의 `com.apple.FinderInfo` 때문에 엄격한 서명 검증에 실패했다. `dmgbuild-settings.py`의 `hide_extensions`가 서명 후 `SetFile -a E`를 호출해 추가한 메타데이터가 원인이다. 설치된 0.1.1도 같은 엄격 검증 오류를 보였다. 패키징을 통과시키기 위해 검증을 약화하거나 복사 후 메타데이터를 지우지 않았다. `35a01c9`에서 해당 옵션만 제거하고 설정 테스트를 갱신했다.

최종 프리뷰:

- 소스 커밋: `7a55f95b2c05` (이후 검증 문서 커밋은 별도). `35a01c9`·`769858c` 프리뷰는 중간 검증 산출물이다.
- 파일: `build/artifacts/TidyTap-0.1.1-preview-developer-id-7a55f95b2c05/TidyTap-0.1.1-preview-developer-id-7a55f95b2c05.dmg`.
- SHA-256: `926efcc2a298a46964be3c82729d4965794c27fdbfefa8e64269f4733b7f45b7`.
- 앱·Helper·DMG의 Developer ID 서명, 타임스탬프, 같은 팀 확인.
- DMG 읽기 전용 마운트, 앱 복사, 복사본의 `codesign --verify --deep --strict` 통과.
- 새 앱과 Helper에 기존 설치 0.1.1의 designated requirement를 각각 적용한 `codesign --verify --strict -R` 검증 통과.
- DMG 체크섬 sidecar 검증 통과.

## 현재 Mac 업데이트 검증

사용자가 현재 Mac에서 기능·업데이트 검증을 선택하여 진행했다.

- 기존 앱과 TidyTap preferences, symbolic hotkeys, HIToolbox를 `/tmp/tidytap-before-update.7o2yca`에 백업했다. 임시 디렉터리이므로 장기 백업 용도로 간주하지 않는다.
- 기존 UI와 Worker를 종료한 뒤 `/Applications/TidyTap.app`을 최종 프리뷰로 교체했다. 실행 중 Worker 자동 교체 시험과 구분되는 종료 후 재실행 업데이트다.
- 설치 앱의 엄격한 서명 검증 통과. 새 앱 PID `84201`, Worker PID `84205`가 동일 설치 경로에서 실행됐다.
- 권한 재승인 조작 없이 Worker가 현재 접근 가능 상태를 반환했다. 새 UI에는 손쉬운 사용만 표시된다. 기존의 휠 반전·고정 단계 3줄·측면 버튼·로그인 설정이 유지되고 적용 완료 상태를 확인했다.
- UI에서 Caps Lock을 켜자 `outcome=applied`, 실제 Caps Lock→F18 HID 매핑, `capsLockOwnership.phase=applied`를 확인했다. 기존 `(null)` 읽기 실패는 실제 설치 앱에서도 해소됐다.
- 사용자가 마우스 정상 동작을 확인했다. 개별 장치·속도별 고정 단계나 모든 트랙패드 제스처 검증을 별도로 완료했다는 의미는 아니다.
- 사용자는 물리 키로 한·영이 전환되지 않았으며 해당 키보드의 Caps Lock 위치 키를 이미 다른 키로 재매핑했다고 보고했다. 키보드 재매핑 계층과 실제 HID 입력을 분리 측정하지 않았으므로 물리 Caps Lock 전환은 미검증으로 남긴다. 기존 사용자 재매핑은 변경하지 않았다.
- UI에서 Caps Lock을 꺼서 적용 완료를 확인했다. HID 매핑은 빈 배열 `()`로 돌아갔다(초기 `(null)`과 동일한 무매핑 의미). 전체 symbolic hotkeys 도메인은 백업과 같았고, 기능 설정도 기존 값과 일치했다. `capsLockOwnership`은 삭제됐으며 나머지 마우스·로그인 설정은 유지됐다.
- 최종 설치 앱은 서명된 프리뷰다. 공증 또는 공개 릴리스 발행은 수행하지 않았다. 기존 앱은 백업 디렉터리의 `TidyTap.app` 및 실제 이동된 `Replaced.app`에 보관했다.
- 복원 후 사용자는 한·영 전환이 된다고 보고했다. 당시 TidyTap Caps Lock 토글은 꺼짐, HID 매핑은 빈 배열이므로 원래 키보드 매핑·단축키가 복원된 상태의 동작으로 기록한다. TidyTap의 물리 Caps Lock 기능 인수 결과와 혼동하지 않는다.

### 입력 모니터링 제거 후 재실행

사용자가 입력 모니터링 항목을 직접 삭제했다. 오케스트레이터가 시스템 설정의 입력 모니터링 화면에서 `항목 없음`을 읽어 확인했다. 권한을 변경하거나 다시 추가하지 않았다.

기존 앱·Worker를 종료한 뒤 새 앱 PID `98373`, Worker PID `98393`으로 다시 실행했다. 새 요청 `025C418F-9998-4DA4-8806-E87DE165A2B9`의 Worker 응답에서 접근 가능을 확인했고, 휠 반전·고정 단계·측면 버튼 설정이 `outcome=applied`였다. 별도 입력 모니터링 목록 등록 없이 입력 처리 시작이 가능한 것을 현재 Mac에서 확인했다. 사용자 마우스 정상 보고는 재시작 전이며 재시작 후 물리 마우스 동작까지 별도 보고받은 것은 아니다.

## 검증 범위 구분

현재 Mac에서 실제 설정 적용·비활성화 복원은 확인했지만 물리 Caps Lock 전환 성공을 뜻하지 않는다. 입력 모니터링 목록 제거 후 새 Worker의 입력 처리 시작도 확인했으나, 과거 권한 이력이 없는 새 계정의 최초 승인 순서까지 검증한 것은 아니다. 기존 권한 데이터의 과거 요청 이력은 복원할 수 없다.

다음은 아직 완료되지 않았다.

- 새 계정에서 손쉬운 사용만 승인한 최초 설치와 물리 마우스·트랙패드 검증.
- 재매핑되지 않은 실제 Caps Lock 입력의 전환, 로그인 실행, 실행 중 Worker 자동 교체.

공증 자격 증명은 아직 구성되지 않았다. 프리뷰는 공증된 공개 릴리스와 구분하며, 기존 공개 DMG·태그를 덮어쓰지 않는다.
