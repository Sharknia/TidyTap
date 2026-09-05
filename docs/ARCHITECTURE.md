# TidyTap 아키텍처

이 문서는 `docs/MVP_PLAN.md`의 0.0.2 범위를 구현하기 위한 최소 프로세스·모듈 경계를 고정한다. 이 문서에 없는 기능, 프로필, daemon, 시스템 확장은 MVP에 추가하지 않는다.

## 1. 프로세스 구성

```text
TidyTap.app (AppKit, Dock 앱)
  ├─ 단일 설정 창 및 토글
  ├─ 권한 상태 표시 / 시스템 설정 열기
  ├─ UserDefaults(preferences domain) 읽기·쓰기
  └─ DistributedNotificationCenter 설정 변경 알림
                    │
                    ▼
TidyTapHelper (LSUIElement, 단일 백그라운드 프로세스)
  ├─ 설정 재읽기 및 적용 조정
  ├─ Caps Lock → F18 / 입력 소스 설정 적용
  ├─ 단일 CGEventTap (휠·측면 버튼)
  └─ 입력 기능 적용 후 필요 시 종료
```

`TidyTap.app`은 Dock에 보이는 일반 AppKit 설정 앱이다. `Command-Q`는 이 프로세스만 종료한다. helper는 Dock에 표시하지 않으며, 앱이 종료된 뒤에도 켜진 입력 기능을 계속 처리한다. 모든 입력 기능이 꺼지면 helper는 event tap을 제거하고 종료한다.

## 2. 모듈 및 파일 경계

실제 파일명은 다음 경계를 유지하는 범위에서 정할 수 있다. 앱과 helper가 공유해야 하는 타입은 공용 모듈에만 둔다.

| 모듈/예상 파일 | 소유 책임 | 소유하지 않는 것 |
| --- | --- | --- |
| `Shared/Preferences.swift` | 세 기능 토글, 로그인 옵션, 백업 메타데이터가 담긴 Codable/UserDefaults 모델과 preferences domain 키 | 이벤트 탭, UI |
| `Shared/IPC.swift` | 설정 변경 알림과 상관관계가 있는 적용 요청/결과 계약 | 설정 저장, 기능 적용 |
| `App/main.swift`, `App/AppDelegate.swift`, `App/SettingsViewController.swift` | 강하게 보유한 delegate로 `NSApplication` 실행, AppKit 창, 한국어/영어 문자열, 토글과 권한 상태 표시 | HID/event tap 구현 |
| `App/SettingsCoordinator.swift` | 사용자 변경 검증, UserDefaults 저장, helper 시작 요청, IPC 알림 | 이벤트 콜백 |
| `App/PermissionCoordinator.swift` | 접근성·입력 모니터링 상태 확인 및 시스템 설정 열기 | 권한 우회, 권한 자동 승인 |
| `App/LoginItemCoordinator.swift` | `SMAppService`로 helper 로그인 항목 등록/해제 및 상태 표시 | helper 기능 토글 |
| `Helper/main.swift`, `Helper/HelperAppDelegate.swift` | 강하게 보유한 delegate로 helper `NSApplication` 실행, 전체 설정 초기 적용, IPC 수신, 종료 조건 | 설정 UI |
| `Helper/ApplyCoordinator.swift` | 설정 스냅샷을 읽어 Caps/이벤트 탭 적용 순서 조정, 트랜잭션과 롤백, 결과 보고 | 개별 이벤트 판정 |
| `Helper/CapsLockController.swift` | Caps Lock HID 매핑의 백업·충돌 검사·적용·조건부 복원 | 입력 소스 단축키, 다른 키 매핑, UI |
| `Helper/InputSourceShortcutController.swift` | 입력 소스 단축키의 현재값 확인, F18 설정 및 조건부 백업 복원 | HID 매핑, 입력 소스 목록 변경 |
| `Helper/EventTapController.swift` | 단일 `CGEventTap` 생성·권한 실패 처리·비활성 콜백 재활성화·제거 | Caps Lock 설정 |
| `Helper/ScrollController.swift` | 마우스 분류 규칙에 따른 VXE 수직 line scroll만 반전 | 트랙패드 제스처 수정, 속도/가속 수정 |
| `Helper/SideButtonController.swift` | 전면 앱이 Safari/Finder일 때 button 3/4를 `Command-[`/`]`로 1회 합성하고 원본 소비 | 앱별 프로필, 다른 앱 입력 수정 |
| `Helper/MenuBarController.swift` | 레거시 트랜잭션/launch-smoke 호환 seam (no-op) | 상태 항목 또는 메뉴 |

개별 controller는 다른 controller의 내부 상태를 직접 변경하지 않는다. `ApplyCoordinator`만 설정 스냅샷을 전달하고, 복원 순서와 실패 결과를 취합한다.

## 3. 설정 저장 및 IPC

설정 앱과 helper는 사용자 Library의 하나의 TidyTap preferences domain을 사용한다. 설정 앱은 각 변경에 단조 증가하는 `applyRequestID`(UUID)를 생성하고, 전체 설정 스냅샷과 함께 저장한 뒤 `DistributedNotificationCenter`에 고정된 변경 알림을 게시한다. 알림에는 설정값을 싣지 않는다. helper는 알림을 받으면 1초 안에 domain 전체와 `applyRequestID`를 다시 읽고 현재 적용 상태와 비교하여 필요한 controller만 갱신한다. helper는 시작 시에도 반드시 전체 설정을 읽는다.

helper가 실행되지 않은 상태의 알림은 큐에 쌓이지 않아도 된다. 다음 helper 시작 시 저장된 스냅샷이 기준이다. 동시에 여러 알림이 오면 마지막으로 읽은 전체 스냅샷 하나를 적용하며, 적용 중에는 serial coordinator로 재진입을 막는다.

helper는 같은 preferences domain의 별도 status 키에 `applyRequestID`, 성공/실패 상태, 실패한 구성요소, 사람이 읽을 수 있는 오류 코드, 실제로 남은 유효 설정 스냅샷을 원자적으로 기록하고, `TidyTapApplyResult` 알림에 동일한 ID를 담아 앱에 반환한다. 앱은 자신이 보낸 ID와 일치하는 결과만 현재 토글 상태에 반영한다. 앱이 결과 알림을 놓쳐도 시작할 때 status 키를 다시 읽어 유효 설정을 복원한다. 설정 저장 실패나 일치하는 적용 결과가 실패인 경우 토글을 성공 상태로 표시하지 않고 오류/권한 상태를 표시한다.

적용은 helper 내부의 직렬 트랜잭션이다. 새 스냅샷을 검증하고, 변경 전 각 controller의 복원 가능한 상태를 캡처한 뒤 Caps(HID와 단축키), event tap 순서로 적용한다. Caps 단계에서 `CapsLockController`가 HID 매핑을 소유하고, 성공한 뒤 `InputSourceShortcutController`가 단축키를 소유한다. 어느 단계든 실패하면 이미 변경한 항목을 역순으로 롤백한다. 롤백도 실패하면 원본 이벤트를 통과시키고 실패 상태와 복구 필요 상태를 보고한다. 전체 적용이 성공한 경우에만 새 `applyRequestID`를 활성 상태로 확정한다.

## 4. 세 기능의 소유와 매핑

| UI 토글 | helper 구성 | 적용 조건 |
| --- | --- | --- |
| Caps Lock으로 입력 소스 전환 | `CapsLockController` + `InputSourceShortcutController` | Caps 토글만 켜져 있으면 helper가 실행된다. Caps Lock HID 항목과 F18 단축키를 각각 백업·검증 후 적용한다. |
| 마우스 휠 수직 방향 반전 | `EventTapController` + `ScrollController` | 접근성 및 입력 모니터링 권한이 모두 있고 토글이 켜진 동안에만 scroll callback이 VXE line-based 수직 값의 부호를 반전한다. 수평·트랙패드·알 수 없는 연속 scroll은 통과시킨다. |
| Safari와 Finder에서 측면 버튼으로 뒤로/앞으로 | `EventTapController` + `SideButtonController` | 접근성 권한이 있고 토글이 켜진 동안, 전면 앱이 Safari/Finder일 때만 button 3/4의 down에서 탐색 키를 한 번 합성하고 해당 down/up을 소비한다. 다른 앱에서는 그대로 통과시킨다. 측면 버튼 전용 경로는 입력 모니터링 권한을 요구하지 않는다. |

두 입력 기능은 하나의 `CGEventTap`을 공유한다. 둘 다 꺼지면 tap을 제거한다. 권한 거부/회수 시 해당 토글은 활성으로 확정하지 않고 원본 이벤트를 수정하지 않는다. Caps 기능은 계획서의 전제대로 접근성·입력 모니터링 권한 없이 동작해야 한다. 휠 토글의 게이트는 접근성+입력 모니터링, 측면 버튼 토글만 켠 경우의 게이트는 접근성이다.

## 5. helper 시작·종료와 SMAppService

helper의 번들 식별자는 앱이 등록할 수 있는 login item helper로 고정한다. `LoginItemCoordinator`는 `SMAppService.mainApp`이 아닌 helper 번들에 해당하는 ServiceManagement 등록 API를 사용하여 `로그인할 때 시작` 토글을 등록/해제하고, 그 상태를 읽어 UI에 반영한다. 등록은 로그인 시 helper가 실행되도록 하는 것뿐이며 현재 프로세스를 강제로 종료하지 않는다.

- 핵심 기능 토글 중 하나가 켜지면 설정 앱이 helper를 실행/활성화한다.
- `로그인할 때 시작`이 켜져 있으면 ServiceManagement가 다음 로그인 직후 helper를 시작하고, helper는 저장된 전체 설정을 복원한다.
- 로그인 실행을 끄면 다음 로그인 자동 시작만 해제한다. 현재 세션의 활성 기능과 helper는 유지한다.
- 모든 세 기능이 꺼지면 helper는 Caps 상태를 필요한 방식으로 복원하고 event tap을 제거한 뒤 종료한다.
- 설정 앱 종료나 `Command-Q`는 helper를 종료시키지 않는다. helper가 비정상 종료된 뒤 자동 재시작은 제공하지 않으며, 사용자가 앱을 다시 열어 복구한다.

이미 실행 중인 helper를 설정 앱이 매번 새로 만들지 않도록 단일 인스턴스/활성화 요청을 사용한다. helper가 설정 변경 중 종료되더라도 고정 modifier나 mouse-down 상태를 남기지 않도록 각 callback의 합성 상태를 button-up 또는 종료 경로에서 정리한다.

## 6. 권한 경계

Caps Lock 전용 경로와 helper 시작은 권한을 요청하지 않는다. 휠 경로는 접근성 및 입력 모니터링 권한을 모두 검사하고, 측면 버튼 전용 경로는 접근성 권한만 검사한다. 권한이 없거나 회수되면 event tap은 원본 이벤트를 통과시키고, 해당 토글은 켜진 것처럼 저장/표시하지 않는다. 사용자가 권한 버튼을 누른 경우에만 실제 사용 프로세스인 helper가 공개 CGRequest API를 호출한다. 앱이 다시 전면에 오면 UUID로 연결된 읽기 전용 요청/결과를 통해 helper의 현재 상태를 확인하며, 이 확인은 설정·Caps 저널·event tap을 변경하지 않는다.

콜백은 필요한 이벤트 종류, 버튼, 스크롤 값, 전면 앱 확인만 메모리에서 즉시 처리한다. 키 입력·마우스 좌표·이벤트 원문을 저장하거나 네트워크로 보내지 않는다. 타사 유틸리티를 종료·제거하거나 권한을 우회하지 않는다.

## 7. 백업·복원 소유권

`CapsLockController`는 기존 HID 매핑의 백업과 복원만 소유한다. 활성화 전 충돌을 검사하고, 기존 매핑 배열에 TidyTap의 Caps Lock→F18 항목만 추가한다. 비활성화 때는 현재 배열에서 TidyTap이 만든 정확한 항목만 제거한다. `InputSourceShortcutController`는 입력 소스 단축키의 백업과 복원만 소유한다. 현재 값이 TidyTap이 설정한 F18과 같을 때만 백업값으로 복원한다. 사용자가 중간에 값을 바꿨으면 덮어쓰지 않고 충돌 상태를 보고한다. helper는 두 변경의 정확한 before/after 계획을 `prepared` 저널로 먼저 저장하므로 HID만 반영된 시점이나 단축키 plist 기록 후 활성화 전 시점에 종료되어도 다음 시작에서 남은 단계만 검증·완료한다. 커밋된 저널과 F18 단축키는 남았지만 재부팅으로 휘발성 HID 매핑만 사라진 경우에는 다른 Caps Lock 매핑이 없음을 확인한 뒤 HID 항목만 재적용한다. 두 controller의 변경 순서·검증·역순 롤백은 `ApplyCoordinator`가 단일 트랜잭션으로 조정한다. 다른 HID 매핑은 어떤 경우에도 덮어쓰거나 제거하지 않는다.

앱 삭제를 감지하여 자동 복원하지 않는다. 지원 제거 절차는 모든 토글과 옵션을 끄고, Caps 백업 복원 및 helper 종료를 확인한 후 앱을 종료·삭제하는 순서이며 README에도 동일하게 기록한다.

## 8. 실패 및 중단 경계

단계 0에서 마우스/트랙패드 분류, Safari/Finder 탐색, helper 독립 실행, Caps 설정·조건부 복원 중 하나라도 검증되지 않으면 UI 구현을 진행하지 않는다. 이 문서는 그 실패를 기능 확장으로 우회하지 않는다. helper의 충돌 자동 재시작, 별도 daemon/system extension, 앱별 프로필과 사용자 지정 매핑은 모두 MVP 밖이다.
