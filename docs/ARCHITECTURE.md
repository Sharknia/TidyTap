# TidyTap 아키텍처

이 문서는 현재 `0.1.4` 개발 브랜치의 구현 경계를 설명한다. 공개 0.1.4에 이미 병합된 최초 설치 수정과 이 브랜치의 **미출시** 클립보드 히스토리·Sparkle 업데이트를 구분한다. 초기 0.0.2 설계는 Git 이력의 이전 버전을 참고한다.

## 프로세스와 소유권

```text
/Applications/TidyTap.app
  ├─ TidyTap (AppKit 설정·히스토리 패널·Sparkle)
  ├─ TidyTapHelper (입력 처리·클립보드 감시·붙여넣기)
  ├─ LaunchAgent plist (로그인 시 같은 Helper 실행)
  └─ Sparkle framework 및 updater services
```

설정 창은 일반 Dock 앱이다. `⌘Q`는 앱만 종료하고 켜진 기능의 Helper는 계속 실행한다. Helper는 `NSApplication`을 만들지 않아 두 번째 설정 앱으로 등록되지 않는다. 모든 입력 기능과 클립보드 히스토리를 끄면 Helper가 복원·정리 후 종료한다. 로그인 실행은 `SMAppService.agent`를 사용하며 기존 내부 실행 파일과 같은 권한 주체 `com.sharknia.TidyTap` 아래에서 동작한다. 별도 root daemon이나 시스템 확장은 없다.

앱과 Helper는 각각 사용자별 `flock`을 보유한다. 같은 앱의 두 번째 실행은 종료되고, 생산 앱은 `/Applications/TidyTap.app`에서만 시작한다. 새 앱이 시작할 때 같은 서명의 다른 TidyTap이 남아 있으면 충돌을 알리고 시작을 막으며, 실행 중 다른 복사본이 나타나면 앱의 후속 작업을 중단한다. 로컬 격리 시험은 별도 preferences suite를 사용한다. [실행 경로](../Sources/App/main.swift), [Helper 잠금](../Sources/Helper/main.swift), [설치본·서명 판별](../Sources/Shared/TidyTapProduct.swift)이 기준이다.

## 설정·입력 적용

설정 스냅샷은 [TidyTapSettings.swift](../Sources/Shared/TidyTapSettings.swift)의 사용자 preferences domain에 저장한다. 앱이 요청 ID를 포함한 변경 알림을 보내면 Helper가 전체 스냅샷을 다시 읽고, [ApplyCoordinator.swift](../Sources/Helper/ApplyCoordinator.swift)가 직렬 적용·실패 복원·결과 보고를 맡는다. 앱은 일치하는 요청 ID의 결과만 성공으로 표시한다. 0.1.4에서는 로그인 항목이 아직 없는 신규 설치에서도 일반 기능 토글을 적용할 수 있게 했고, 실패 뒤 Helper 종료 직전의 새 요청을 보존했다. [0.1.4 릴리스 노트](RELEASE_NOTES_0.1.4.md)에 검증 범위가 있다.

Caps Lock은 HID 매핑과 입력 소스 단축키의 백업·조건부 복원을 사용한다. 휠 방향·단계 크기, Safari/Finder 측면 버튼, Finder 파일 잘라내기와 클립보드 호출 키는 입력 엔진의 event tap 경로를 공유한다. Finder `⌘X`는 파일 이동 대기 상태를 관리하고, 일반 `⌘C`는 복사로 둔다. 클립보드 히스토리는 최초 단축키 입력과 적용 성공 전에는 수집하지 않는다. 기존 입력 기능과 Finder 동작의 상세 수용 범위는 [MVP 계획](MVP_PLAN.md), [Finder 검증](FINDER_CUT_PASTE_VALIDATION.md), [클립보드 수용 현황](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md)을 참고한다.

## 클립보드 히스토리 — 미출시 프리뷰

Helper의 [ClipboardCaptureService.swift](../Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardCaptureService.swift)는 새 복사에 대한 지원 텍스트·이미지를 읽는다. [ClipboardHistoryStore.swift](../Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardHistoryStore.swift)는 본문을 preferences와 분리해 `~/Library/Application Support/com.sharknia.TidyTap/clipboard-history`에 보관한다. 최근 복사 또는 성공 응답을 받은 히스토리 붙여넣기 요청은 같은 항목을 맨 위로 올리고 7일 보관 시점을 갱신한다. 완전히 같은 내용·서식의 재복사는 한 항목만 남긴다. 상한은 7일·100개·총 50 MiB·항목당 10 MiB다. 기능을 끄면 수집만 멈추며 기존 기록은 만료 때까지 남는다.

Helper는 호출 대상 PID·세션 ID만 앱에 알리고, 앱의 [ClipboardHistoryPanelController.swift](../Sources/App/ClipboardHistoryPanelController.swift)가 검색·목록·미리보기를 표시한다. 선택한 기록 ID와 붙여넣기 방식은 다시 Helper에 보낸다. Helper가 대상 앱·입력 위치를 검사한 다음 시스템 클립보드에 항목을 쓰고 붙여넣기 키 이벤트를 전송한다. 전송 성공 응답은 **대상 앱이 실제로 삽입했다는 확인이 아니다**. 취소는 클립보드를 바꾸지 않고, 자체 붙여넣기 쓰기는 새 복사로 재수집하지 않는다. 읽기 거부는 손쉬운 사용 권한과 별도로 처리한다. [URS](CLIPBOARD_HISTORY_URS.md)와 [수용 현황](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md)은 요구와 확인된 증거를 구분한다.

## 업데이트·배포 — 미출시 프리뷰

설정 앱은 Sparkle 2로 `main/appcast.xml` 주소의 피드를 자동 확인하도록 구성됐고 **업데이트 확인** 버튼을 제공한다. 설치는 사용자가 눌러야 한다. `appcast.xml`은 현재 브랜치에만 있는 빈 뼈대여서 공개 주소에서는 아직 업데이트를 제공하지 않는다. 프리뷰를 실행한다고 기존 공개 0.1.4 설치본이 자동으로 교체되는 것은 아니다. Sparkle 설치 직전에 Helper 종료를 요청하고 잠금 해제를 기다린 뒤 새 앱의 Helper를 시작한다. 서명·공증·EdDSA appcast 및 첫 수동 교체 절차는 [릴리스 문서](RELEASE.md)에 있다. 현재 브랜치의 서명 프리뷰와 공개 릴리스는 별개다.

## 권한과 정보 경계

손쉬운 사용 권한은 마우스·Finder·클립보드 단축키/붙여넣기에 필요하고, Caps Lock 전용 경로에는 필요하지 않다. 입력 모니터링 목록을 독립 승인 대상으로 표시하지 않는다. 클립보드 읽기는 별도로 확인하며, 최초 활성화 때 현재 내용을 한 번 읽을 수 있지만 소급 저장하지 않는다. 키 입력·마우스 좌표·원본 이벤트를 저장하거나 전송하지 않는다. 히스토리를 켠 뒤의 지원 복사 내용은 위 로컬 저장소에 기록한다. 업데이트 요청에는 그 내용을 넣지 않는다. 권한 주체의 이전 검증은 [권한 문서](PERMISSION_OWNERSHIP.md)에, 클립보드의 아직 남은 실제 OS 검증은 [수용 현황](CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md)에 있다.
