# 최초 설치 수정 검증 기록

작성일: 2026-09-07  
브랜치: `fix/first-run-permissions-capslock`  
상태: 구현·독립 리뷰·통합 검증 진행 중

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
- HID 변경과 오류 메시지 변경은 각각 새 솔의 독립 리뷰에서 실제 결함 없음. 권한 후속 수정과 DMG 수정도 각각 새 솔의 독립 리뷰에서 실제 결함 없음. 최종 통합 리뷰는 진행 중이다.
- 사용자 요청으로 `origin/dev`를 `ad5eb3a`까지 fast-forward했다. PR #16·#17의 병합 대상은 `main`이었다. 현재 `origin/dev`, `origin/main`, `v0.1.1`이 같은 기준을 사용한다.
- 권한 독립 리뷰에서 과거 미응답 `.request(.inputMonitoring)`이 업데이트 시 재실행될 수 있음을 발견했다. `769858c`에서 해당 요청을 읽기 전용 응답으로 처리하도록 수정하고 startup·재처리 회귀 테스트를 갱신했다. 손쉬운 사용 요청은 유지한다.
- 최종 코드 `769858c`의 앱 테스트도 96개 통과, 실패·건너뜀 0개다. 결과: `build/first-run-tests/Logs/Test/Test-TidyTap-2026.09.07_10-37-30-+0900.xcresult`. 후속 launch smoke도 같은 비변경·프로세스 조건으로 통과했다.
- 오류 문구 독립 리뷰 중 기존 `HelperLauncherTests.testDynamicIdentityDetectsReplacementWhenAdHocDesignatedRequirementChanges`의 종료 후 프로세스 개수 assertion이 한 번 실패했다. 리뷰어의 단독 재실행과 두 번의 통합 전체 실행에서는 통과했다. 이번 변경의 회귀로 확정하지 않았고, 해당 기존 테스트는 수정하지 않았다.

## 서명 프리뷰

첫 실제 패키징은 DMG 복사 앱의 `com.apple.FinderInfo` 때문에 엄격한 서명 검증에 실패했다. `dmgbuild-settings.py`의 `hide_extensions`가 서명 후 `SetFile -a E`를 호출해 추가한 메타데이터가 원인이다. 설치된 0.1.1도 같은 엄격 검증 오류를 보였다. 패키징을 통과시키기 위해 검증을 약화하거나 복사 후 메타데이터를 지우지 않았다. `35a01c9`에서 해당 옵션만 제거하고 설정 테스트를 갱신했다.

최종 프리뷰:

- 소스 커밋: `769858cdc712` (이후 검증 문서 커밋은 별도).
- 파일: `build/artifacts/TidyTap-0.1.1-preview-developer-id-769858cdc712/TidyTap-0.1.1-preview-developer-id-769858cdc712.dmg`.
- SHA-256: `ec9f116d2032961d9a321e0ee1e0ae6742b7a41031ab0394d338b2fbad18ec02`.
- 앱·Helper·DMG의 Developer ID 서명, 타임스탬프, 같은 팀 확인.
- DMG 읽기 전용 마운트, 앱 복사, 복사본의 `codesign --verify --deep --strict` 통과.
- 새 앱과 Helper에 기존 설치 0.1.1의 designated requirement를 각각 적용한 `codesign --verify --strict -R` 검증 통과.
- DMG 체크섬 sidecar 검증 통과. 실제 `/Applications/TidyTap.app`은 교체하거나 실행 상태를 변경하지 않았다.

## 검증 범위 구분

읽기 전용 준비 단계 성공은 물리 Caps Lock 전환·복원 성공을 뜻하지 않는다. 단위 테스트의 가짜 권한 상태는 새 계정의 TCC 승인을 대신하지 않는다. 기존 권한 데이터의 과거 요청 이력은 복원할 수 없다.

다음은 아직 완료되지 않았다.

- 통합 독립 리뷰의 최종 결과.
- 새 계정에서 손쉬운 사용만 승인한 최초 설치와 물리 마우스·트랙패드 검증.
- 실제 Caps Lock 적용·전환·복원, 로그인 실행, 0.1.1에서 업데이트 후 권한 유지.

공증 자격 증명은 아직 구성되지 않았다. 프리뷰는 공증된 공개 릴리스와 구분하며, 기존 공개 DMG·태그를 덮어쓰지 않는다.
