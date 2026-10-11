# macOS 27 hidutil 호환성 수정 계획

## 문제와 근거

- 2026-10-11 사용자는 macOS 업데이트 직후 여러 입력 기능이 멈췄다고 확인했다.
- 현재 환경: macOS 27.0.1, TidyTap 0.2.5 / build 13. 시작 기준 main: `0a59a05`.
- 앱과 plain helper는 실행 중이고 손쉬운 사용 권한은 허용됨이다.
- 저장된 적용 결과: `failed / capsLock / capsLock.invalidSystemData.hidMappings`.
- `hidutil property --get UserKeyMapping`은 `RegistryID Key Value` 표와 장치별 `(null)` 또는 여러 줄 OpenStep 배열을 반환한다.
- 기존 `MacOSSystemApplyAdapter.decodeHIDMappings`는 단일 `(null)`, JSON dictionary, plist/OpenStep 배열만 지원한다.
- `ApplyCoordinator`가 기존 상태를 캡처하면서 이 오류를 만나면 event tap 적용 전에 반환한다. 그래서 마우스, Finder, 클립보드 호출도 활성화되지 않는다.
- 진단 중 사용자 설정에서 이미 활성화된 Caps Lock → F18 매핑을 한 번 복원했다. 전체 service 조회에는 동일 매핑과 `(null)`이 함께 존재하며, `--matching keyboard` 조회의 세 keyboard service는 동일 매핑이다. 이 수동 복원을 해결 완료로 취급하지 않는다.

## 목표와 범위

1. macOS 27 장치별 표와 기존 macOS 출력 형식을 모두 지원한다.
2. 최초 unscoped 출력이 표 형식일 때만 키보드 매핑의 읽기와 쓰기에 동일한 keyboard 선택 조건을 사용한다. 기존 출력에서는 기존 unscoped 명령을 유지한다.
3. 여러 keyboard service의 매핑이 같을 때만 기존 단일 매핑 트랜잭션을 사용한다. 다른 매핑을 합치거나 임의로 한 장치를 선택하지 않는다.
4. 기존 Caps Lock ownership, symbolic hotkey 백업, pre-write 상태 검증, rollback 검증을 유지한다.
5. UI 및 clipboard focus 로직, 설정 트랜잭션의 전반적 재설계는 이번 패치 범위에서 제외한다. 캡처 실패 시 effectiveSettings가 사용자 요청을 보여주는 문제는 알려진 후속 개선 대상으로 기록한다.

## 구현안 — 아스트라 검수 반영

- 최초 unscoped 조회가 정확한 새 표 header이면 `--matching '{"PrimaryUsagePage":1,"PrimaryUsage":6}'`로 전환한다. legacy JSON / OpenStep / XML / 단일 null이면 기존 unscoped 명령을 유지한다. 현행 OS 도움말과 실제 read로 explicit JSON matching을 확인했다. 구버전 matching 지원을 추측하여 강제하지 않는다.
- 선택한 scope는 adapter 수명 동안 고정한다. read / prewrite / set / postread / rollback은 동일한 scope를 사용한다. matched 실패 시 unscoped 쓰기로 fallback하지 않는다. 최초 read 전에 apply를 호출하면 scope 확정·조회 검증을 먼저 수행하고 실패하면 쓰지 않는다. 도중 legacy↔table 형식 전환도 오류로 처리한다.
- matching은 같은 선택 조건일 뿐 여러 호출 사이 장치 집합 고정을 보장하지 않는다. hotplug로 null/nonempty 또는 서로 다른 매핑이 섞이면 전체 설정 적용이 실패할 수 있다. hotplug 자동 재적용은 이번 범위에 넣지 않는다.
- 정확한 표 header를 식별하고 RegistryID / `UserKeyMapping` / value 블록을 분리한다. RegistryID는 디코딩 경계에만 사용하고 진단 문서나 릴리즈 로그에 실제 값을 보관하지 않는다.
- 각 value는 기존 decoder로 처리한다. null과 빈 OpenStep 배열은 빈 매핑이다. 여러 줄 배열 및 whitespace / CRLF를 지원한다.
- header만 있는 출력, 잘린 배열, 잘못된 row, 중복 RegistryID, 다른 key, 알 수 없는 값, 다른 장치 매핑은 `invalidSystemData(.hidMappings)`로 중단한다. OS 버전 번호로 출력 형식을 추측하지 않는다.
- 장치별 매핑이 동일하지 않은 경우 기존 전역 ownership 모델로 안전하게 표현할 수 없으므로 실패 처리하고 쓰지 않는다. 순서만 다른 배열도 보수적으로 중단한다.
- 원시 `hidutil` 출력이나 `(null)`을 임의의 빈 값으로 처리하여 오류를 숨기지 않는다.

## 검증과 수용 조건

- 실제 출력 형태를 식별자를 제거한 fixture로 재현한다: all-null 표, 동일 Caps Lock 배열 표, 무관한 매핑 보존 표.
- 기존 JSON / OpenStep / XML 출력, 단일 null, empty 및 malformed 출력의 회귀 검증.
- 표의 header-only / 중복 ID / 잘못된 key / 잘린 값 / 장치별 다른 매핑 / null과 nonempty keyboard 혼합 / CRLF 검증.
- fake runner로 read와 write가 동일 keyboard matching scope를 쓰는지 확인한다. 잘못된 표에서 controller commit이 쓰지 않는지 확인한다.
- 실제 production adapter + fake runner에서 준비 후 commit 직전 mixed 상태가 되면 HID 쓰기 0회, set 이후 일부 장치만 바뀌면 성공 거부 및 rollback 덮어쓰기 중단을 검증한다.
- 기존 `.applied` / `.prepared` durable journal을 실제 표 decoder와 연결하여 restart 재적용·비활성화·중단 복구를 검증한다. all-null + 기존 hotkey/ownership의 reboot 유사 복구, mixed 상태의 journal 보존, 모든 keyboard가 다시 일치한 이후의 재시도를 검증한다.
- 실제 macOS 15.1~26 runtime은 이번 기기에서 검증하지 못한다. legacy fixture와 기존 명령 경로 보존을 검증하며 이를 실제 구OS 실행 완료로 기록하지 않는다. 실제 재부팅도 별도 확인 전 완료로 주장하지 않는다.
- input engine 전체 테스트, 앱 전체 테스트, launch smoke, release build settings와 릴리즈 workflow 회귀 검사.
- production adapter로 현재 keyboard 조회를 읽기만 수행해 fixture와 실제 OS 결과가 일치하는지 확인한다.
- 서명·공증한 최종 main 빌드를 로컬에 설치할 때 기존 앱을 복구 가능한 위치에 백업하고 설정·히스토리를 보존한다. 기존 앱/helper와 같은 designated requirement를 확인한다.
- 실제 설정 UI에서 적용 성공과 권한 허용을 확인하고, clipboard shortcut으로 패널이 열리는지 확인한다. 물리 Caps Lock / 휠 / 측면 버튼 / Finder 입력은 실제 확인한 범위만 기록한다.

## 아스트라 검수 및 병합 순서

1. 이 계획서를 gpt-6-astra에 검수받는다. 수정 범위, 다중 장치 보존, 구버전 호환성, rollback, 실제 검증 공백을 점검하고 지적을 반영한 뒤 구현한다.
2. 구현과 테스트 후 아스트라가 최종 diff를 검수한다. 유효한 지적을 수정하고 다시 테스트·검수한다.
3. feature branch → dev PR: 정확한 최종 commit 검수, CI / check 확인 후 merge한다. 생성한 PR은 이 chat에 연결한다.
4. dev → main PR: 통합 diff와 버전·릴리즈 문서를 검수하고 check 확인 후 merge한다. 필요 시 위 수정·검수 순서를 반복한다. review 승인 전에 merge하지 않는다.
5. 선택한 버전: 사용자 승인 `0.2.6`, build 14. app과 helper 버전이 같아야 한다.

## 릴리즈

- latest published version / tag / branch / clean worktree를 다시 확인한다. 기존 공개 tag와 산출물을 덮어쓰지 않는다.
- 이미 로컬에 존재하는 ignored signing config와 Keychain만 사용하고 값을 출력하지 않는다. 최종 main commit의 clean checkout에서 `Scripts/package-release-dmg.sh`를 실행한다.
- exact DMG를 `Scripts/verify-release-artifact.sh`로 검사한다. Developer ID, app/helper/Sparkle nested signatures, notarization, stapling, Gatekeeper, SHA-256, LaunchAgent layout과 버전을 확인한다.
- 검증한 main commit에 새 `v0.2.6` tag와 GitHub Release를 게시한다. 그 뒤 검증한 DMG를 가리키는 Sparkle appcast를 별도 PR로 검수·병합하여 dev와 main에 반영한다.
- 공개 Release asset과 checksum, appcast signature / version / URL을 다시 읽어 배포 완료를 확인한다.
- 자격 증명, 외부 검수, signing / notary가 실제로 막힌 경우 실패 단계를 기록하고 미검증 빌드를 공개하지 않는다.

## 검수·실행 기록

- 계획 검수: 2026-10-11 gpt-6-astra가 adaptive scope, 고정된 scope의 실패 처리, journal/partial-write/hotplug 검증 조건을 반영하는 안을 승인했다. 최초 전OS matching 강제안은 채택하지 않았다.
- 구현 검수: 2026-10-11 gpt-6-astra 승인. 유효한 P1/P2 차단 지적 없음. adaptive scope, 실패 후 쓰기 차단, hotplug/부분 적용 및 기존 journal 연결 테스트를 확인했다.
- main 검수: gpt-6-astra가 PR #53 head `e37abdf9dcc80e68b37289248faad0a52e3e8082`를 승인했다. main merge `d1314f748888eef7f7a4b1fe416b9eac90ce3213`의 tree가 승인한 구현과 같음을 확인했다.
- release 검수: gpt-6-astra가 exact DMG와 sidecar, 서명·공증·Gatekeeper·버전·plain helper·LaunchAgent·설치 앱과 산출물 일치를 독립 검사하고 v0.2.6 게시를 승인했다.
- 구현 [PR #52](https://github.com/Sharknia/TidyTap/pull/52), main 통합 [PR #53](https://github.com/Sharknia/TidyTap/pull/53) 병합 완료.
- 공개 릴리즈: [TidyTap 0.2.6](https://github.com/Sharknia/TidyTap/releases/tag/v0.2.6). `v0.2.6`은 위 main merge commit을 가리킨다.

### 구현 검증 (2026-10-11, macOS 27.0.1 / Xcode 27.0)

- 수정 전: 추가한 null-table / keyboard-table 조회 회귀 테스트 2개가 기존 오류로 실패했다.
- 수정 후: input engine 전체 134개, 실패 0. live opt-in 테스트 1개는 기본 실행에서 건너뛴다.
- 실제 OS 읽기만 수행하는 opt-in 검사: 1개 통과, 동일 키보드 매핑 1개를 두 번 읽었다. 시스템 매핑 쓰기는 수행하지 않았다.
- 앱 전체 177개 통과. 첫 실행의 신규 journal fixture 한 건에서 container existence 기대값이 잘못되어 실패했으며, 기존 baseline을 나타내는 fixture를 바로잡고 전체 재실행했다.
- launch smoke 통과: 격리된 앱·helper 시작/종료·설정 창·운영 설정/HID 상태 보존 검사.
- release / preview DMG workflow 회귀 검사, installer layout 검사, release build settings(`--require-local`) 통과.
- 실제 macOS 재부팅, 구버전 OS 실행, 물리 입력 검증은 이 자동 테스트 결과에 포함하지 않는다.

### 릴리즈 및 로컬 실행 확인

- 최종 main clean checkout에서 `Scripts/package-release-dmg.sh`로 패키징했다. 시스템 Python 3.9는 DMG 도구의 최소 버전을 충족하지 않아 한 번 중단됐으며, Codex bundled Python 3.12.14를 build-only 환경으로 지정하여 같은 스크립트로 성공했다. 소스나 서명 키는 바꾸지 않았다.
- 앱/helper/Sparkle nested code의 Developer ID 서명, DMG 서명·timestamp, Apple 공증·stapling, Gatekeeper 통과. `verify-release-artifact.sh`와 `verify-dmg-sidecar.sh` 통과.
- DMG: `TidyTap-0.2.6.dmg`, 3,506,353 bytes. SHA-256: `4ae8897b5c873804cca0aee43f822c165be5c4e5e30600080f8fd3e442baa067`.
- 공개 Release에서 DMG와 sidecar를 다시 내려받아 위 SHA-256과 동일함을 확인했다.
- 기존 앱과 설정을 로컬에 복구 가능한 형태로 백업한 뒤 exact DMG의 앱을 `/Applications/TidyTap.app`에 설치했다. 앱/helper designated requirement가 기존 앱과 같고 설치된 실행 파일이 DMG와 일치함을 확인했다.
- 실제 UI: 0.2.6, 손쉬운 사용 허용, ‘변경 사항이 적용되었습니다’. Caps Lock 설정 OFF → ON 실제 경로 모두 `applied`, 마지막 사용자 settings 전체와 effectiveSettings가 원래 값과 같다. durable journal은 `.applied`다.
- 사용자가 다른 앱에서 물리 `⌥V`를 눌러 ‘히스토리가 정상적으로 열립니다’라고 확인했다. 자동 입력 도구의 app-directed 이벤트는 이 물리 검증을 대신하지 않았다.
- 실제 Caps Lock 키 입력·휠·측면 버튼·Finder 파일 이동, 실제 재부팅, 구OS 실행은 이번 실기기 확인 범위에 포함하지 않는다.

### 자동 업데이트 피드의 남은 조건

- DMG 다운로드 릴리즈와 로컬 설치는 완료됐다. 자동 업데이트 feed는 현재 `0.2.5 / build 13`을 유지한다.
- `prepare-update-feed.sh`의 기존 Keychain 공개키 조회가 `No existing signing key found`로 중단됐다. app-specific 계정과 legacy 기본 계정, Sparkle-labelled/service Keychain item을 확인했으나 기존 개인키를 찾지 못했다.
- 기존 앱의 `SUPublicEDKey`와 일치하는 원래 개인키 복원이 필요하다. 새 키 생성·앱 공개키 교체·미서명 enclosure 게시·기존 0.2.5 피드 덮어쓰기는 하지 않았다. 따라서 기존 설치 앱의 자동 업데이트 배포는 완료로 주장하지 않는다.
- 원래 키를 로컬 Keychain에 복원한 뒤 공개키 일치 확인 → exact DMG appcast 서명 → 아스트라 검수 → feature/dev/main PR 병합 → 공개 feed의 URL·버전·길이·서명 재확인을 수행한다.
