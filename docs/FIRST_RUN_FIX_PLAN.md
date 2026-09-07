# 0.1.1 최초 설치 문제: 원인 조사와 수정 작업계획

작성일: 2026-09-07  
상태: 구현·독립 리뷰·자동 검증 및 현재 Mac 업데이트 검증 완료, 최초 승인·물리 Caps Lock 인수 대기
구현 브랜치: `fix/first-run-permissions-capslock` (`origin/dev`의 `b414f80`에서 분기 후 `v0.1.1` 병합)

이 문서는 앞서 작성한 계획서를 삭제한 뒤, 추가 조사 결과로 새로 작성했다. 초기 조사는 읽기 전용으로 진행했으며 이후 사용자 승인으로 구현과 현재 Mac 업데이트 검증을 수행한다.

## 1. 조사 대상과 증거의 범위

- 분석 대상은 `v0.1.1` 태그다. 현재 `dev`는 해당 릴리스의 모든 변경을 포함하지 않으므로, 릴리스의 실제 파일을 `git show v0.1.1:...`로 대조했다.
- 로컬 설치 앱의 `CFBundleShortVersionString`은 `0.1.1`이며, 조사 환경은 macOS 26.5.2 (`25F84`)다. 번들 버전 확인만으로 배포 바이너리 전체가 태그와 일치한다고 검증한 것은 아니다.
- 설치 앱이 저장한 `applyStatus`, `permissionResult`, `permissionRequest`를 읽었다. 현재 permissionRequest는 `refresh`이므로 과거 설정 버튼 클릭 이력은 남아 있지 않다.
- Caps Lock 관련 `SystemTypes.swift`, `SystemApplyAdapter.swift`, `CapsLockController.swift`는 현재 브랜치와 `v0.1.1` 사이에 차이가 없다. 이 제품 소스를 직접 컴파일한 별도 진단 프로그램에서 읽기·준비 단계만 실행했다.
- 권한 요청 분기 테스트 2개를 현재 브랜치에서 실행했다. `xcresult` 결과는 2개 통과, 실패·건너뜀 0개다. 해당 권한 판정·요청 분기는 릴리스 코드와 동일하다. 가짜 provider를 사용한 분기 테스트이며 새로운 macOS TCC 승인 실험은 아니다.
- 사용자 TCC DB는 읽기 권한이 없어 조회하지 못했다. 우회하거나 권한을 변경하지 않았다. 따라서 별도 입력 모니터링 승인 기록의 과거 상태는 사용자 보고를 근거로 삼는다.

## 2. 증상별 원인

### 2.1 손쉬운 사용만 허용했는데 입력 모니터링도 허용 표시

**확인된 코드 결함: 이벤트 수신 가능 여부를 별도 입력 모니터링 승인 상태로 표시한다.**

`Sources/Helper/InputFeatureAdapters.swift`의 `CGTidyTapPermissionProvider.currentState()`는 `CGPreflightListenEventAccess()`의 반환값을 `inputMonitoring.authorized`로 바꾼다. UI는 이를 입력 모니터링 항목의 “허용됨”으로 표시한다.

Apple DTS는 손쉬운 사용이 이벤트 전송과 수신을 모두 허용하며, 입력 모니터링은 수신을 허용한다고 설명한다. 따라서 손쉬운 사용으로 수신이 가능한 상태는 별도 입력 모니터링 토글 승인과 같지 않다. 읽기 가능 여부를 반환하는 API의 오류가 아니라, 앱의 상태 모델과 사용자 문구가 API 의미를 과장한 것이다.

설치 앱이 저장한 실제 결과도 `accessibility=authorized`, `inputMonitoring=authorized`다. 다만 이 결과가 생성된 순간의 TCC 토글을 독립적으로 기록한 자료는 없다.

참고: [Apple DTS의 권한 관계 설명](https://developer.apple.com/forums/thread/828052).

### 2.2 입력 모니터링 설정에 앱이 없어 수동 추가가 필요해 보임

**확인된 제품 원인: 별도 승인이 필요하지 않은 상태에서도 별도 권한 설정 화면으로 안내하는 흐름이다.**

릴리스 코드에서 다음 연결을 확인했다.

1. Worker가 이벤트 수신 가능을 `inputMonitoring.authorized`로 반환한다.
2. `HelperPermissionCoordinator.handleLatestRequest()`는 이미 authorized인 항목에 대해 `CGRequestListenEventAccess()`를 호출하지 않는다.
3. `TidyTapPendingPermissionSettingsOpen.consume(matching:)`는 권한 상태를 보지 않고 일치하는 요청 ID에 대해 설정 화면 대상을 반환한다. 코드 주석에도 이미 승인된 경우 설정 화면을 연다고 명시되어 있다.
4. `AppDelegate.updatePermissionResultIfAvailable()`는 그 대상을 받아 시스템 설정을 연다.

`testHelperDoesNotPromptWhenExplicitPermissionIsAlreadyGranted`와 `testHelperExplicitInputMonitoringRequestUsesInputMonitoringProviderPath`를 실행하여, authorized이면 요청 0회, denied이면 해당 요청 경로를 호출하는 분기를 확인했다.

Apple DTS 설명과 사용자 보고를 결합하면, 손쉬운 사용으로 이벤트 수신은 가능하지만 별도 입력 모니터링 항목은 없는 상태가 성립한다. 목록에 앱이 없다는 사실만으로 기능에 필요한 권한이 부족하다고 판단할 수 없다. 따라서 해결 목표는 무조건 목록에 등록하는 것이 아니라 불필요한 별도 승인 안내를 없애는 것이다.

**역사적 사실의 한계:** 당시 클릭 시 요청 API가 실제로 생략됐다는 실행 로그는 없다. 요청 생략만을 목록 미등록의 유일한 원인으로 단정하지 않는다. 확인한 것은 보고된 상태에서 재현 가능한 앱 분기와 그 안내 결함이다.

### 2.3 Caps Lock: “변경사항을 적용할 수 없습니다”

**실제 실패 원인 확인: 무매핑 출력 `(null)`의 파싱 실패다.**

설치 앱의 저장 상태:

```text
outcome: failed
failedComponent: capsLock
errorCode: capsLock.invalidSystemData.hidMappings
effectiveSettings.capsLockInputSourceSwitching: false
```

실제 제품 코드를 컴파일해 실행한 읽기 전용 진단 결과:

```text
enabledSelectableInputSourceCount(): 2
hidutil property --get UserKeyMapping: (null)
decodeHIDMappings("(null)\n"): invalidSystemData(hidMappings)
decodeHIDMappings("()"): []
decodeHIDMappings("[]"): invalidSystemData(hidMappings)
decodeHIDMappings("garbage"): invalidSystemData(hidMappings)
CapsLockFeatureController.prepareEnablePlan(): invalidSystemData(hidMappings)
InputSourceShortcutController.prepareEnable(): passed
```

`PropertyListSerialization`은 `(null)`을 문자열 원소 배열로 읽지만, `decodeHIDMappings()`는 딕셔너리 배열만 허용하므로 실패한다. 입력 소스 2개 검사를 통과한 뒤 HID 읽기에서 실패하며, HID·단축키를 쓰는 단계에는 도달하지 않는다.

단축키 준비를 별도로 실행했을 때 현재 값을 읽고 변경안을 만드는 데 성공했다. 따라서 현재 관찰된 실패는 입력 소스 개수나 기존 단축키 충돌 때문이 아니다. 설정 쓰기·활성화·복원 성공은 실행하지 않았으므로 아직 검증하지 않았다.

추가 표시 결함도 있다. `SettingsViewController.showApplyStatus()`는 Caps Lock 오류 코드를 구분하지 않고 일반 실패 문구로 축약한다. 내부에는 구체적 오류가 있지만 사용자는 원인을 알 수 없다.

## 3. 수정할 동작

### A. 손쉬운 사용 중심으로 권한 UI 정리

- 마우스 기능의 사용자용 필수 권한 안내는 손쉬운 사용으로 통일한다. 입력 모니터링을 두 번째 필수 승인 항목으로 표시하거나 수동 추가를 요구하지 않는다.
- 근거: 0.1.1 마우스 이벤트 처리는 `.defaultTap`으로 이벤트를 수정하고, 측면 버튼은 탐색 키를 전송한다. 단순 수신 승인만으로 완료되는 기능 경로가 아니다. 제스처 감시는 `NSEvent.addGlobalMonitorForEvents`를 사용한다.
- 내부 이벤트 수신 가능 검사와 실제 탭 생성 실패 검사는 유지한다. 별도 권한 행을 없애는 것과 실행 가능성을 무조건 승인하는 것을 혼동하지 않는다.
- 손쉬운 사용은 있으나 필요한 이벤트 접근이나 탭 생성에 실패하면 실제 기능 오류로 안내한다. 별도 입력 모니터링 승인이 부족하다고 단정하지 않는다.
- 권한 상태는 실제 Worker에서 다시 조회한다. 미확인·거부·승인·회수, 설정 복귀, Worker 재시작을 구분한다.
- 명시적 손쉬운 사용 설정 버튼은 승인된 상태에서도 관리 목적으로 열 수 있다. 문제가 되는 입력 모니터링 전용 안내와 버튼을 제거한다.
- 기존 저장·IPC의 `inputMonitoring` 값은 내부 호환성 검토 없이 삭제하지 않는다. 필요한 경우 수신 가능이라는 내부 의미를 명시하고 사용자 문구와 분리한다. 이 수정에 불필요한 IPC 전면 개편을 포함하지 않는다.
- `IOHIDRequestAccess()` 추가, 비공개 TCC 조회, 권한 초기화, 별도 온보딩 추가는 수정 범위가 아니다.

주요 파일: `Sources/Helper/InputFeatureAdapters.swift`, `Sources/App/SettingsCoordinator.swift`, `Sources/App/SettingsViewController.swift`, `Sources/App/AppDelegate.swift`, `Sources/Shared/TidyTapSettings.swift`, `Sources/Shared/Localizable.xcstrings`. 엔진 권한 계산은 UI 변경과 일치하는지 검토하되 실제 접근 확인을 약화하지 않는다.

### B. 무매핑 상태를 정상 처리

- `SystemApplyAdapter.decodeHIDMappings()`에서 앞뒤 공백·개행을 제거한 정확한 `(null)` 출력을 빈 배열로 정규화한다.
- 기존 JSON 객체와 OpenStep 형식을 보존한다. 실제 출력 근거 없이 지원 형식을 확대하지 않는다.
- 빈 바이트·알 수 없는 문자열·잘못된 매핑을 빈 배열로 취급하지 않는다. 실패를 무매핑으로 오인하면 기존 설정을 덮어쓸 수 있다.
- Caps Lock 매핑 충돌·소유권·쓰기 전 비교·쓰기 후 검증·복원 계약은 유지한다.

주요 파일: `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/SystemApplyAdapter.swift`, `SystemApplyAdapterTests.swift`, `CapsLockControllerTests.swift`.

### C. 실패 원인을 사용자에게 표시

- 기존 `errorCode`를 활용하여 입력 소스 개수, 기존 Caps Lock 매핑 충돌, 소유권 충돌, 매핑 읽기 실패, 적용 확인 실패, 복원 필요 상태를 구분한다.
- 읽기 실패를 “키보드 설정이 충돌했다”고 번역하지 않는다. 원인별 문구와 가능한 조치를 한국어·영어로 제공한다.
- 알 수 없는 오류에는 일반 실패 문구를 유지한다. 내부 명령 출력 전체를 노출하지 않는다.
- 실패·부분 적용·복원 필요 상태의 토글은 실제 `effectiveSettings`와 일치시킨다.

주요 파일: `SettingsCoordinator.swift`, `SettingsViewController.swift`, `TidyTapStrings.swift`, `Localizable.xcstrings`.

### D. 검증 중 발견된 DMG 서명 손상 방지

서명 프리뷰의 실제 마운트·복사 검증에서 기존 `hide_extensions` 옵션이 서명된 앱에 `FinderInfo`를 추가해 검증을 실패시키는 것을 확인했다. 배포 후보 검증을 진행하기 위한 최소 수정으로 해당 옵션만 제거하고 Python 설정 테스트를 갱신한다. 설치 레이아웃 재설계나 검증 우회는 포함하지 않는다.

## 4. 실행 순서와 검증

1. **구현 기준 확보:** `v0.1.1`을 포함하는 최신 릴리스 계열 기준점을 확인하고 `fix/first-run-permissions-capslock`에서 구현한다. 현재 `dev`를 그대로 배포하면 0.1.1 기능이 빠질 수 있으므로 고정 휠 단계·Worker 교체·DMG 변경을 보존한다.
2. **파서 회귀 테스트와 수정:** 현재 실패하는 `(null)` 사례를 먼저 추가하고 정상 무매핑, 정상 기존 매핑, 잘못된 입력을 구분한다.
3. **권한 UI와 실패 안내 수정:** 상태·설정 이동·Worker 응답 테스트 및 한·영 화면 테스트를 갱신한다.
4. **관련 자동 테스트 실행:** 입력 엔진 테스트와 앱 테스트를 실행하고 실패가 없는지 확인한다. 구현 기준 브랜치의 README 명령을 사용한다.
5. **서명된 실제 설치 앱 검증:** 새 계정 또는 깨끗한 검증 환경에서 손쉬운 사용만 승인한 뒤 마우스·트랙패드와 Caps Lock을 직접 확인한다. 기존 사용자의 TCC를 일괄 초기화하지 않는다.
6. **업데이트·문서 검증:** 0.1.1에서 업데이트했을 때 기존 설정·소유권·Worker 교체를 확인하고 README 및 `docs/PERMISSION_OWNERSHIP.md`의 현재 안내를 갱신한다. 과거 검증 기록은 보존한다.

| 검증 영역 | 필수 사례 | 완료 기준 |
| --- | --- | --- |
| HID 파서 | `(null)`, 공백·개행, `()`, 기존 JSON/OpenStep, 손상 입력 | 정상 무매핑만 빈 배열로 처리 |
| Caps Lock | 무매핑 켜기·끄기, 다른 키 매핑 공존, Caps Lock 충돌 | 한·영 전환 성공, 사용자 설정 보존, 충돌 시 쓰기 거부 |
| 권한 UI | 모두 미승인, 손쉬운 사용만 승인, 수신만 가능, 권한 회수 | 실제 사용 가능 상태와 안내 일치, 별도 입력 모니터링 승인 오표시 없음 |
| 설정 이동 | 최초 권한 요청, 승인 후 관리, 설정 복귀 | 입력 모니터링 수동 추가 요구 없음, Worker 재조회 |
| 마우스 실동작 | 휠 반전, 고정 단계, 측면 버튼, 트랙패드 | 기존 기능 유지, 권한 충족 후 실제 동작 |
| 생명주기 | UI 종료·재실행, Worker 재시작, 로그인 실행, 업데이트 | 권한 주체와 설정 유지, 구형 Worker 결과 혼동 없음 |
| 오류 안내 | 읽기 실패·개수·충돌·확인 실패·복원 필요 | 구체적 문구, 실제 적용 상태, 한국어·영어 일치 |

자동 테스트는 OS 승인 실험의 대체가 아니다. 각 실제 검증에는 macOS 버전, 앱 버전·커밋·서명·설치 경로, 승인 순서, 실제 Worker, 결과를 기록한다. 물리 장치나 로그인 검증을 하지 못하면 미검증으로 명시하며 완료로 처리하지 않는다.

## 5. 완료 조건과 비범위

- [x] 입력 모니터링을 별도 승인한 것처럼 표시하지 않고 수동 추가를 요구하지 않는다. (코드·테스트·오프스크린 화면 확인)
- [ ] 손쉬운 사용만 승인한 최초 설치 환경에서 관련 마우스 기능을 실제 검증한다.
- [ ] `(null)` 환경에서 Caps Lock 활성화·전환·비활성화·복원이 성공한다. (실제 활성화·비활성화·설정 복원 확인, 재매핑되지 않은 물리 Caps Lock 전환은 미검증)
- [x] 기존 키 매핑을 보존하고 실제 실패 이유를 표시한다. (기존 트랜잭션 테스트 및 한영 UI 테스트; 물리 복원은 아래 검증 기록 참조)
- [ ] 관련 자동 테스트, 설치·업데이트 검증과 문서 갱신을 완료한다. (자동 테스트·현재 Mac 종료 후 업데이트·문서 갱신 완료, 최초 승인·로그인·실행 중 Worker 교체는 미검증)

사용자 승인으로 제품 코드 수정·병렬 위임·독립 리뷰·단계별 커밋/푸시를 시작한다. 릴리스 발행과 배포 버전·일정 확정은 포함하지 않는다. 조사 당시의 과거 TCC 호출 이력이 없다는 한계와 수정 후 실동작 검증이 남아 있다는 사실을 전체 원인 미확인 또는 검증 완료로 바꾸어 표현하지 않는다.

## 6. 실행 분담과 서명 연속성

- 루나: 최소 UI 및 오류 문구 설계 점검. 코드 변경 없음.
- 테라: HID 무매핑 파서와 회귀 테스트.
- 솔: 권한 UI·요청·Worker 상태 흐름. 기존 IPC 호환성 유지.
- 테라: Caps Lock 오류 메시지 변환과 한국어·영어 번역, 관련 테스트.
- 각 구현 완료 후 별도의 새 솔이 구현자 대화 없이 diff와 요구사항을 독립 리뷰한다.
- 오케스트레이터: 코드 통합, 범위·중복 추상화 검수, 통합 테스트·서명 검증, 단계별 커밋과 원격 푸시.

새 Mac의 Developer ID Application 팀은 기존 0.1.1과 같은 `V9SQZ6B7RP`다. 기존 앱의 임시 복사본을 새 인증서로 서명하여 앱과 Helper가 기존 designated requirement를 충족하는 것을 확인했다. 수정 앱에서도 이 조건을 확인한다. 개인 키·로컬 서명 설정은 Git에 포함하지 않는다. 공증 인증은 아직 설정되지 않았으므로 공증·배포 완료를 주장하지 않는다.

진행 결과와 미검증 항목은 [검증 기록](FIRST_RUN_VALIDATION.md)에 유지한다. 사용자 추가 요청에 따라 `origin/dev`도 `ad5eb3a`로 최신화했다.
