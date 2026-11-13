# 고정 보관함·전체 히스토리 iCloud 동기화 개발 계획

- 작성일·개정일: 2026-11-13, 개정 0.5
- 목표 제품 버전: **0.3.0**. 문서 개정 번호와 구분한다. 버전 상향·빌드·배포는 구현/출시 단계에서 수행한다.
- 기준 코드: `main` 8d1f219. 현재 제품은 파일 기반 로컬 저장이다.
- 상태: 사용자 결정 반영·관리형 후보 우선 검증 계획. Core Data 모델·제품 코드·계정·클라우드 자원은 아직 변경하지 않았다.
- 확정: 보관함 1개, 일반 히스토리와 고정 항목 동기화, 같은 Apple 계정의 Mac 간 사용, 설정의 ON/OFF.
- 이번 추가 확정: OFF는 일시중지다. ON에서 OFF 중 쌓인 유효한 기록·변경과 원격 기록을 합친다. Core Data 관리형 동기화를 먼저 검증하고 합격 시 채택한다.
- UI 확정: 항상 최근 기록으로 열기, 최근 기록/보관함 탭, 패널 내부 전용 ⌘1/⌘2와 마우스. [UI 작업 계획](CLIPBOARD_PINBOARD_UI_WORK_PLAN.md), [기존 URS](CLIPBOARD_HISTORY_URS.md).

## 1. 목표와 선택 이유

최근 텍스트·서식·이미지를 다시 찾고, 자주 쓸 항목은 고정하며 다른 Mac에서도 사용할 수 있게 한다. 로컬 사용과 기록은 네트워크 없이 유지한다. iPhone/iPad 앱·키보드, 여러 보관함·공유·OCR·항목 편집은 이번 범위가 아니다.

우선 후보는 Core Data 로컬 저장과 NSPersistentCloudKitContainer의 개인 CloudKit 미러링이다. 로컬 변경과 삭제 이력을 프레임워크가 함께 관리하는 경로를 먼저 시험한다. 앱이 영구 삭제 감사 로그나 생성 수신증 프로토콜부터 직접 만들지는 않는다. 내부 이력이 없다는 뜻은 아니며, 제품의 고정·만료·중복 정책은 앱 책임으로 남는다.

기존 파일+CKSyncEngine은 대안이다. 관리형 후보가 실제 ON/OFF·삭제·고정·용량·프로세스 요구를 충족하지 못하면 실패 근거를 적고 다시 비교한다. 파일 재사용만으로 직접 전송 상태·삭제·복구 구현이 더 작다고 단정하지 않는다. 두 방식을 동시에 제품에 연결하지 않는다. 최종 모델의 CloudKit schema 배포와 지원하는 관리형 구·신 버전의 호환성도 제품 채택 조건으로 확인한다.

| 결정 | 상태 |
| --- | --- |
| OFF=일시중지, ON=유효한 로컬/원격 기록 병합 | 사용자 확정. OFF 중 새 복사를 영구 비공개로 분리하는 모드는 만들지 않음 |
| Core Data 관리형 후보 우선 검증 | 사용자 확정. 검증 전 제품 저장소 교체 확정은 아님 |
| 개인 DB·단일 미러링 소유자 | 기술 기준. 실제 실행 주체·서명/수명은 Gate0에서 확인 |
| 고정/일반 수명·삭제 범위·충돌·동기화 후 한도 | 아래 기준안 및 Gate1의 선결 설계. 기존 동작과 새 제안을 구분 |

## 2. 사용자 동작과 ON/OFF 의미

| 사건 | 약속할 동작 |
| --- | --- |
| OFF | 로컬 수집·검색·고정·삭제는 각 기능 설정대로 계속 사용. 새 클라우드 송수신을 중지하는 전환을 요청하고 로컬/원격 기록은 지우지 않음 |
| 끄는 중 | 실행 중 import/export와 저장소 전환 정리가 아직 확인되지 않은 상태. 이미 서버가 받은 변경을 되돌린다고 약속하지 않음 |
| 꺼짐 완료 | 비미러링 로컬 상태의 사용과 이후 새 송수신 차단을 실제로 확인한 상태. 설정 Bool만 false라고 완료 표시하지 않음 |
| ON·재실행 | 같은 계정의 기존 store·식별자·이력/미러링 메타데이터를 사용해 재개. OFF 중 유효한 새 복사·고정·삭제도 원격 변경과 조정 |
| 네트워크 없음 | 저장·사용은 유지하고 동기화는 대기. OFF와 네트워크 장애를 구분 |
| 계정 변경 | 이전 계정 store·이력을 새 계정에 자동 반입하지 않음. 열린 패널을 닫고 계정별 연결을 다시 확인 |
| 설정 | 수집과 독립된 기기별 옵션. 기본 꺼짐 기준안. 스위치 설명에 ‘다시 켜면 보관 중인 기록과 변경도 동기화됩니다’ 표시 |

‘합친다’는 양쪽 목록의 단순 합집합이 아니다. 새 항목은 추가하고, 삭제 이력은 삭제를 반영하며, 중복과 고정 변경은 정한 규칙으로 병합한다. 원격에 없다는 이유로 로컬을 삭제하거나 삭제한 항목을 전부 재업로드하지 않는다. 만료됐거나 이미 삭제된 기록을 OFF/ON으로 복원하지 않는다.

OFF는 이 Mac 전용 영구 보관 모드가 아니다. 다만 계정이 바뀌거나 계정 귀속이 불명확한 데이터까지 자동 병합한다는 허가는 아니다. Gate1에서 계정 없는 기록의 귀속·최초 반입을 명시하고 이전 계정의 데이터를 새 계정에 전송하지 않는다.

## 3. 유지할 동작과 아직 결정할 정책

| 항목 | 유지·기준안·미정 구분 |
| --- | --- |
| 최근 사용 | 현재 코드대로 복사 또는 붙여넣기 시도 시작 시각으로 갱신. 실패도 되돌리지 않음. 원격 import만으로 시각을 갱신하지 않음 |
| 일반 기록 | 기존 7일·1,000개·총 50MiB·항목10MiB가 출발점. 50MiB는 기존 .clip 직렬화 합계이며 앱 전체 디스크의 절대 상한은 아님 |
| 동기화 후 한도 | 공통 라이브러리 한도인지 기기별 표시/캐시 한도인지 Gate1에서 확정. 로컬 캐시 퇴출을 무조건 mirrored 객체 delete로 바꾸지 않음 |
| 중복 | 본문+지원 서식이 같으면 최신 1건으로 보이는 기존 동작 유지. 동시 import·고정·별도 ID를 처리할 결정적 규칙 필요. Core Data CloudKit 유일성 제약에 의존하지 않음 |
| 고정 | 일반 기록의 만료·개수·용량 정리로 고정 보관 본문을 자동 삭제하지 않음. 고정의 수명과 일반 기록 소속을 분리. 저장 모델은 Gate1에서 확정 |
| 고정 해제 | 기준안: 고정 목록에서는 해제만 제공. 유효한 일반 기록은 남기고 만료/삭제된 일반 기록을 해제만으로 복원하지 않음 |
| 고정 항목 사용 | 기준안: 일반 기록에서 만료된 고정 전용 항목도 사용 시 같은 논리 ID로 일반 목록에 재등록하고 고정 유지 |
| 일반 기록 삭제 | 기준안: 해당 일반 기록 소속은 원격에도 제거하되 고정 보관은 유지. 전체 데이터 영구 삭제와 구분 |
| 전체 삭제 | 현재 알고 있는 ID만 지울지 미수신 기록까지 초기화할지, 고정 보존과 버튼 문구를 Gate1에서 확정. 임의 세대 초기화는 추가하지 않음 |
| 순서·고정 한도 | 보관함 순서·고정 저장 한도는 Gate1 결정. 초과 시 기존 고정 내용을 자동 삭제하지 않는 기준 유지 |

동기화 지연은 충돌 부재의 근거가 아니다. 삭제/늦은 재전송, 고정/해제, 만료/원격 고정 또는 최근 사용, 전체 삭제/오프라인 새 복사, 동시 중복을 각각 다룬다. 구현 전에 입력 사건·최종 일반/고정 수·삭제 상태·사용 시각을 명시한다. Core Data 기본 merge policy 하나가 이 제품 정책을 모두 만족한다고 가정하지 않는다.

주기는 시스템 자동 import/export 일정이다. 고정 N초 폴링·초 단위 완료·항상 최신을 보장하지 않는다. 일반 Core Data fetch는 로컬 조회이며 서버 강제 새로고침 API처럼 표시하지 않는다. 기존 ‘재시도’ UI는 실제 실패 복구/재연결 계약에 맞게 Gate0에서 정하고 내부 CloudKit zone을 직접 고치는 방식으로 구현하지 않는다.

## 4. 검증 구조와 구현 경계

### 관리형 저장소·프로세스

- Gate0는 격리된 probe로 프레임워크의 정상 삭제·재개·두 프로세스 접근을 확인한다. 최종 제품 schema를 이 실험만으로 고정하지 않는다.
- probe 모델은 ProbeStore.swift에서 코드로 만드는 `ProbeEntry` 한 개다. 속성은 `id: UUID?`, `lastUsedAt: Date?`, `payload: Data?`, `isPinned: Bool`(기본 false)이며 유일성 제약은 쓰지 않는다. payload는 기존 ClipboardCapturedContent의 직렬화 값이고 external binary 저장을 허용한다. 기존 로컬 엔진 패키지를 참조해 지원 형식을 재사용한다. id/lastUsedAt/payload는 새 항목 생성 때 반드시 채운다. 이 단일 모델로 최종 고정/일반 소속과 모든 충돌 정책을 검증했다고 하지 않는다.
- 같은 SQLite URL·모델 버전 `ClipboardCloudKitProbe.v1`을 ON/OFF와 별도 writer 프로세스에 사용한다. writer는 같은 probe 실행 파일의 writer 모드로 로컬 컨테이너만 열고 합성 항목을 저장한다. history tracking과 remote-change notification 옵션은 양쪽에서 켠다. 미러링 소유자만 CloudKit 옵션을 사용한다. 실제 입력 Helper 통합은 별도 P1/P3 수용이다.
- 미러링 소유 프로세스는 하나다. 주앱 소유를 먼저 시험하며 아래 실행 수명 기준안으로 판정한다. Helper는 현재 독립 실행 파일이므로 권한을 추가하는 것만으로 미러링 주체가 된다고 가정하지 않는다.
- 앱·Helper가 같은 Core Data store에 직접 쓸 경우 동일 모델·store URL/계정, context별 transaction author, 소비자별 persistent history token, 원격 변경 알림 뒤 재조회/병합을 검증한다. NSManagedObject/context를 프로세스·actor 사이에 전달하지 않고 UI에는 값 snapshot을 준다.
- `.clip` 디렉터리를 iCloud Drive로 옮기거나 Core Data가 관리하는 CloudKit record/zone을 CKSyncEngine으로 동시에 수정하지 않는다. 대안은 별도 재설계 후 선택한다.

실행 수명 기준안은 다음과 같다. 사용자 확정 사항과 구분하며 Gate0-A에서 시험 요구로 잠근 뒤 probe를 작성한다. 다른 수명이 필요하면 조사 결과와 함께 계획을 먼저 개정한다.

| 사건 | 수집·미러링 기준안 |
| --- | --- |
| 설정 창/임시 패널 닫기 | 켜진 Helper 수집과 ON 미러링은 계속. 창 수명 때문에 미러링 소유자를 자동 종료하지 않음 |
| 주앱 명시적 ⌘Q | 기존 Helper 수집은 유지. 주앱 소유 미러링은 중단을 허용하고 다음 주앱 실행 때 저장된 ON 의도로 재개. 종료 중 상태를 최신/완료로 표시하지 않음 |
| 로그인/업데이트 후 | 기존 로그인 설정에 따른 Helper 수집 유지. 주앱 소유자는 다음 주앱 실행 때 ON 재개. 동기화 스위치로 로그인 항목을 자동 활성화하지 않음 |

### OFF/ON 전환의 기술 검증

후보 경로는 ON의 미러링 store를 정상 종료/정리한 뒤 같은 로컬 SQLite store를 비미러링 구성으로 열어 OFF 동안 저장하고, ON에서 같은 계정·store UUID·이력을 유지해 미러링을 다시 연결하는 방식이다. 기존 store description의 cloudKitContainerOptions만 바꾸거나 컨테이너 변수만 해제하면 즉시 멈춘다고 가정하지 않는다. 공개 API의 구성/종료 동작과 실제 관찰을 Gate0에서 확인한다.

전환 중에는 저장 요청이 전환 중인 store에 잘못 도착하지 않게 직렬화한다. 로컬 작업을 성공으로 표시한 뒤 버리지 않는다. 전환 실패는 ‘오류/끄는 중’으로 남기고 새 빈 store를 만들어 복구했다고 하지 않는다. 이미 서버가 수락한 작업과 OFF 완료 뒤 새 작업을 구분해 기록한다. 동일 store의 보존·재개와 송수신 중지가 확인되지 않으면 관리형 후보를 합격으로 처리하지 않는다.

### 변경 이력·설정·진단

Core Data의 persistent history와 미러링 메타데이터를 사용한다. 앱 별도 영구 삭제 감사 로그·생성 수신증·CKSyncEngine.State.Serialization을 주 경로에 추가하지 않는다. 프레임워크 내부 삭제 추적이 불필요하다는 뜻은 아니다. 일반 기록의 7일 만료로 아직 export/소비되지 않은 이력을 지우지 않고, 소비자 token·성공한 export·안전한 정리 범위를 Gate1에서 결정한다.

동기화 의도는 기존 preferences 도메인의 독립 Bool 키 `clipboardICloudSyncEnabled`에 저장한다. 누락 기본값은 false다. 입력용 Codable snapshot·request ID·apply status·로그인 항목은 바꾸지 않는 scalar read/write 경로를 사용한다. 동기화 스위치는 기존 입력 설정 save를 호출하지 않고 전용 delegate/Coordinator 경로로 저장한다. 저장 성공과 실행 주체 적용 성공은 분리하며 입력 Helper 오류가 동기화 의도를 되돌리지 않는다. [UI 계획](CLIPBOARD_PINBOARD_UI_WORK_PLAN.md)의 이 계약을 유지한다.

기존 AppDelegate/TidyTapClipboardPasteLog의 검색어·본문 미리보기·내용 hash는 이관 전에 비기록으로 바꾸고 이전 로그 정리를 확인한다. 성공/실패 붙여넣기·계정 전환·로그 정리 실패를 합성 표식으로 시험한다. 원문·토큰·키 파일을 로그나 fixtures에 넣지 않는다. 진단에는 가명 ID·유형·크기·시각·오류 코드만 쓴다.

### 이관·구버전 경계

새 store는 Application Support의 `clipboard-library-v2` 아래에서 계정별로 구분한다. 구 `clipboard-history` 파일에는 새 형식을 쓰지 않는다. 실제 파일명·SQLite 부속 파일·계정 없는 영역·모델 버전은 Gate1에서 확정한다.

전환 전에 기존 앱/Helper writer의 신원·종료·잠금 해제를 확인하고 구 파일을 백업한다. staging store에 본문·서식·이미지·사용 시각을 이관해 개수/체크섬·중복·한도를 검사하고 완료 표시 후 새 writer를 시작한다. SQLite 본체만 복사하고 WAL/SHM/외부 binary 파일을 빠뜨리지 않도록 지원되는 store 백업/이관 절차를 사용한다.

중단된 이관은 부분 결과를 동기화하지 않고 원본에서 검증·재개한다. 검증 전 원본을 지우지 않으며 백업 보존/정리 조건도 Gate1에 적는다. 구버전은 구 스냅샷만 보고 새 v2 데이터는 건드리지 못하게 한다. 재업그레이드에서 옛 파일 전체를 다시 생성해 삭제 기록을 부활시키지 않도록 반입 ledger/충돌 경계를 설계한다. 안전한 식별 불가 시 자동 재반입을 멈추고 기존 v2를 보존한다.

로컬 저장 보호는 현행의 디렉터리 0700·본문 0600과 같은 사용자 전용 수준을 유지한다. 라이브러리/계정/staging/백업 디렉터리와 SQLite·WAL/SHM·외부 binary·진단 증거까지 범위에 넣고 생성·재실행·이관·백업 후 권한을 확인한다. Core Data가 만든 부속 파일을 누락하거나 접근 제한을 해제해 오류를 우회하지 않는다. 구체 파일 배치·권한 설정/검사 API는 Gate1에서 확정한다.

### 시험 연결 격리

일반 XCTest·launch-smoke·clipboard gate는 실제 CloudKit 연결을 금지하고 가짜 저장/미러링 경계를 쓴다. 현재 UserDefaults suite/IPC object 격리만으로 클라우드가 격리됐다고 보지 않는다. 잘못된 시험 설정·가짜 주입 누락을 실제 연결로 대체하지 않는다.

실제 probe는 별도 시험 계정·시험 컨테이너·합성 데이터·명시한 private DB/namespace에서 실행한다. 실제 연결 전 후보/서명/프로파일/container/환경/계정 별칭/store 경로와 정리 범위를 기록한다. 실제 이메일·토큰·인증정보는 기록하지 않는다. 최종 제품 후보의 Production 설정 확인도 시험 계정의 분리된 private DB에서 수행한다. 개발 컨테이너의 성공으로 최종 후보를 대체하지 않는다.

여기서 시험 namespace는 시험 계정의 private DB·시험 store UUID·합성 ID 범위다. Core Data 내부 CloudKit zone을 임의로 선택하거나 지우는 API를 제품/시험에 추가하지 않는다. 연결 설정이 없는 probe의 기본 모드는 가짜/로컬 전용이다. 실제 연결은 명시적 실행과 Gate0의 검증된 설정이 모두 있어야 한다.

## 5. 작업 단계·산출물·정확한 파일 경계

| 단계 | 파일·작업 | 통과 조건 |
| --- | --- | --- |
| Gate0-A 조사/프로브 구성 | 생성 예정 `docs/CLIPBOARD_ICLOUD_GATE0.md`. 현재 Developer ID·App ID·컨테이너·프로파일·silent push·소유 프로세스·ON/OFF 전환·실제/가짜 시험 분리 확인. 정확한 probe 파일 목록·모델·연결 영역과 M01~08·12·15 실행 프로토콜을 먼저 기록 | 검증 대상/미확인/수행 범위·접근 조건과 아래 사건별 관찰/중단/판정 계약을 잠근 뒤 probe 코드 작성. 조사만으로 Gate0 전체 통과 아님 |
| Gate0-B 격리 probe | 생성 예정 `Spikes/ClipboardCloudKitProbe/ClipboardCloudKitProbe.xcodeproj/project.pbxproj`, `Spikes/ClipboardCloudKitProbe/Sources/ProbeApp.swift`, `Spikes/ClipboardCloudKitProbe/Sources/ProbeStore.swift`, `Spikes/ClipboardCloudKitProbe/Sources/ProbeScenario.swift`, `Spikes/ClipboardCloudKitProbe/Info.plist`, `Spikes/ClipboardCloudKitProbe/Probe.entitlements`, `Spikes/ClipboardCloudKitProbe/README.md`, `Scripts/run-clipboard-cloudkit-probe.sh` | 6절의 기반 시험을 실행해 결과를 Gate0에 기록. 실제 계정/자원 값과 필요한 추가 파일·모델은 Gate0-A에서 먼저 확정하고 빈 모델을 실제 업무 모델 검증으로 세지 않음 |
| Gate1 제품 저장/정책 설계 | 생성 예정 `docs/CLIPBOARD_LIBRARY_V2_DESIGN.md`. 기존 Reader/Writer 형식·논리 ID·순서/중복·고정/일반 수명·전체 삭제 범위·한도·계정·이관·사용자 전용 로컬 접근/백업 보호·이력 정리·UI API 대응 확정 | 최종 모델의 개발 schema 초기화·검토, Production 승격/모델 버전 배포 순서와 지원 구·신 버전 경계, schema/API/actor·프로세스 계약·사건표 최종값·단계별 생성/수정/삭제 목록을 확정한 후 제품 코드 작성 |
| P1 저장/수집/이관 | 수정 후보 `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardHistoryStore.swift`, `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardCaptureService.swift`, `Sources/Shared/TidyTapProduct.swift`, `Sources/Shared/TidyTapSettings.swift`, `Sources/Helper/InputFeatureAdapters.swift`, `Sources/Helper/FinderFeedbackAppHost.swift`, `Sources/App/AppDelegate.swift` | 기존 형식/한도·민감 표식 제외·고정 ID 조회 유지, 안전 이관·중단/재개·구버전 경계 통과. 새 repository/model 파일은 Gate1 목록에 명시 |
| P2 로컬 UI | `Sources/App/ClipboardHistoryPanelController.swift`, `Sources/App/AppDelegate.swift`, `Sources/Shared/Localizable.xcstrings`, 앱 시험·renderer. 상세는 UI 작업 계획의 U1~U4 | 최근 기록/보관함·⌘1/⌘2·선택/검색/IME·붙여넣기·고정/삭제·언어 검증 |
| P3 미러링/옵션/수명 | `Sources/App/SettingsCoordinator.swift`, `Sources/App/SettingsViewController.swift`, `Sources/App/AppDelegate.swift`, `Sources/Shared/TidyTapSettings.swift`, `Sources/Shared/TidyTapIPC.swift`, `Sources/Helper/HelperRuntime.swift`, `Sources/Helper/HelperLifecycle.swift`, `Sources/Helper/FinderFeedbackAppHost.swift`, `TidyTap.xcodeproj/project.pbxproj` | ON/OFF와 재개·소유자 수명·계정/이력 소비·저장실패·동시수정. 제품 소유자 파일/모델/권한은 Gate1에서 정확 목록 확정 |
| P4 시험/문서/배포 준비 | `Tests/TidyTapTests/SettingsViewControllerTests.swift`, `Tests/TidyTapTests/TidyTapSettingsTests.swift`, `Tests/TidyTapTests/SettingsSnapshotRenderer.swift`, `Tests/TidyTapTests/HelperLauncherTests.swift`, 엔진의 Clipboard 관련 시험. `Scripts/launch-smoke.sh`, `Scripts/test-clipboard-history-gates.sh`, `Scripts/package-preview-dmg.sh`, `Scripts/package-release-dmg.sh`, `Scripts/verify-release-build-settings.sh`, `Scripts/verify-release-artifact.sh`, 패키징 회귀 시험. URS·수용 현황·README·아키텍처·배포 문서 | 검토된 최종 모델 schema의 Production 승격 확인 후, 지원 구·신 관리형 버전 조합과 최종 서명 후보의 두 Mac/지원 OS 수용·서명/프로파일/환경·업데이트·기존 입력 기능 회귀 결과 기록. 공개 배포는 별도 요청 |

표는 현재 계획의 경계다. 코드 작성 전에 Gate0-A/Gate1 문서에서 실제 수정·생성·삭제 경로와 모델/API·필수 검사를 완전한 저장소 상대경로로 확정한다. 기본 삭제 예정 제품 파일은 없다. `initializeCloudKitSchema`는 명시적 Development 준비 경로에서만 사용하고 정상/Production 실행에서는 호출하지 않는다. probe type을 최종 제품 컨테이너에 승격하지 않으며 실제 승격은 별도 실행 범위에서 수행한다. 비공개 signing 설정·프로파일·p8은 저장소에 복사하지 않는다. 생성된 build/clipboard-cloudkit-probe/ 출력만 디렉터리 glob을 허용한다. 새 외부 서버·패키지·두 개의 미러링 엔진은 추가하지 않는다.

Gate0부터 실제 계정 자원을 만들거나 코드를 실행했다는 뜻은 아니다. 당장 허용되는 작업은 조사와 시험 구성의 설계다. 기존 제품을 이관하거나 실제 동기화가 완료됐다고 표시하려면 아래 해당 관문을 통과해야 한다.

## 6. 검증 사건과 합격/실패 판정

| ID | 시험 | 기대 결과·판정 |
| --- | --- | --- |
| M01 | A/B 정상 텍스트·RTF/HTML·PNG/TIFF·최대 항목 송수신 | 같은 논리 항목/서식/이미지 표시. 실제 삽입과 로컬 수신을 구분. 항목10MiB 경계 유지 |
| M02 | 정상 개별/전체 삭제, 고정 보존 | 정한 ID 범위의 일반 기록 삭제 반영. 고정 보존 정책과 일치. 현재 알고 있는 목록과 전체 원격 초기화를 혼동하지 않음 |
| M03 | 첫 요청 실제 미도달 후 연결 | 유효한 로컬 항목이 자동 반영되고 조용히 누락/보류되지 않음 |
| M04 | 서버/B가 생성 확인한 뒤 A 중단·B 삭제·A 재시작 | 옛 항목 재생성 여부 관찰. 삭제된 항목 재생성 시 실패. 실제 ACK 영속화 전 경계를 재현하지 못했으면 해당 경로는 미실행이며 통과로 주장하지 않음. OS/시각/가명ID/관찰 범위 기록 |
| M05 | 생성/이미지 전송 중 삭제·취소·재시작·역순 수신 | 최종 삭제/미전송 상태가 정한 정책대로 수렴. 단순 네트워크 미연결 시험으로 SDK 자동 재시도 경합을 대체하지 않음 |
| M06 | A OFF에서 X 복사·고정/해제·H 삭제, B에서 Y 복사, A ON | 유효한 X/Y·OFF 중 변경 병합. 삭제 H를 목록 합집합으로 복원하지 않음. 이미 만료된 항목은 ON으로 부활하지 않음. 다른 계정 데이터 제외 |
| M07 | ON 중 OFF·정리 중 추가 복사·재실행·빠른 ON/OFF | 저장 의도/전환 상태를 구분, 마지막 요청 세대만 UI 완료 반영. OFF 완료 뒤 새 송수신 0건. 이미 서버가 받은 작업의 되돌림은 약속 안 함 |
| M08 | OFF 동안 로컬 사용·삭제 후 ON, 이력 유지/정리 | 같은 store UUID/이력을 이어 사용. 자동 OFF 정리로 pending 삭제가 사라지지 않음. 아직 export/소비 안 된 이력을 7일 기준으로 지우지 않음 |
| M09 | 7일 경계·시계 차이·동시 고정/재사용 | 정한 고정/만료 결과 유지. import 시각이 최근 사용으로 계산되지 않음. 제어 가능한 사건 최종값은 Gate1에서 잠금 |
| M10 | 같은 본문/서식 동시 복사·중복 수신 | 최신 1건 표시·고정 상태 보존·원격 변경으로 사용 시각 무한 연장 없음. 유일성 제약 없이 처리 |
| M11 | 두 Mac 합산 1,000개/50MiB 초과·최대 이미지·계정/디스크 부족 | 정한 공통/캐시 한도와 삭제 의미 유지. 수신 중 최고점·안정 상태·DB/WAL/이미지/이력 별도 크기 측정. 로컬 퇴출이 뜻하지 않은 원격 삭제가 되면 실패 |
| M12 | UI 앱 종료·Helper만 수집·동시 쓰기·로그인/업데이트 | 위 실행 수명 표에 맞는 소유자 재개·author/token·알림/재조회에 따라 이후 반영. UI 창을 닫았다는 이유로 수집이 누락되지 않으며, 미러링 중단 상태를 최신/완료로 표시하지 않음 |
| M13 | 파일 이관 중 종료·구 writer 잔존·다운그레이드/재업그레이드 | 부분 store 송수신 금지·원본 보존·재이관 중복/삭제 부활 없음. SQLite 부속 파일 포함 |
| M14 | 로그·계정 A→B·이전 callback·오류 | 원문/hash 진단 비기록·구 로그 정리, 이전 계정 본문/변경 자동 업로드 없음. 실패/대기를 완료로 표시 안 함 |
| M15 | XCTest/smoke 잘못된 suite·연결 주입 누락 | 실제 CloudKit 연결 0건. 운영 영역 fallback 금지. 실제 probe만 검증된 시험 연결 사용 |

Gate0-A에서 M01~08·12·15 각각의 사전 상태·합성 ID·행동 순서·관찰 신호·중단 지점·관찰 기간의 실제 값/시작점/재관찰·종료 조건·성공/실패/부분/미실행 판정을 확정한다. M04는 ACK 영속화 전 경계 재현을 인정할 증거, M07은 OFF 완료와 이후 새 송수신 부재를 인정할 증거를 명시한다. 공개 API로 통제/관찰할 수 없는 경계는 미실행으로 남길 조건을 적는다. 진단 증거의 저장 경로·가명화/보관 범위도 잠그고, 그 계약으로 ProbeScenario.swift와 실행 스크립트를 작성한다. 단순 대기나 목록 변화 없음만으로 중단·경합 재현을 증명하지 않는다.

Gate0-B는 M01~08·12·15의 프레임워크/전환/두 프로세스 경로를 우선 실행한다. 최종 제품 모델이 필요한 M02의 고정 보존 전체, M09~14의 business/이관 전체는 Gate1 이후 제품 수용에서 추가 검증한다. 단순 probe 모델의 실패가 제품 모델로 해결 가능한지와 프레임워크 API의 한계인지를 구분한다. 모든 사건의 전체 통과를 probe 결과만으로 선언하지 않는다.

실제 시험에 사용할 두 Mac·시험 계정·서명/프로파일을 확보하지 못하면 해당 관문은 미실행이다. 고정 관찰 기간 안에 미반영이면 상태·오류·시각을 기록하고 부분/미실행으로 두며, ‘영구 대기 없음’을 증명했다고 하지 않는다. UI/가짜 저장 단위 시험으로 실제 Core Data import/export를 대체하지 않는다.

## 7. Gate0·Gate1 완료와 다음 단계

Gate0 보고서에는 성공/실패/미실행, 실제 실행 주체·ON/OFF 전환 방법·시험 연결·프로세스/SDK/OS·probe 모델/파일 목록·증거를 적는다. 정상 삭제가 된다는 사실만으로 미관찰 ACK/복원 경로까지 보장하지 않는다. 창을 닫은 상태의 미러링 유지·권한·명시적 종료 후 재개과 OFF 중 로컬 저장/ON 재조정이 모두 확인돼야 관리형 후보를 통과시킨다.

Gate1에는 논리 schema/API·Core Data 모델/계정 store 배치·고정/일반 소속·중복/순서·삭제/만료·공통 라이브러리/기기별 캐시 한도·이관 원자성·로컬 권한/백업 보호·이력 정리·UI 및 Helper 값 조회 계약, 최종 schema 배포·지원 모델 버전의 공존/업데이트 순서, 정확한 파일 변경과 사건별 기대값을 적는다. 전체 본구현은 그 산출물 뒤에 진행한다. 실패가 확인되면 사용자 확정 OFF 의미·UI·동기화 범위를 유지하고, 실패 원인/대안을 문서화한다.

- 중간·미확인: 관리형 후보의 실제 OFF/ON·삭제·두 프로세스·용량 적합성은 시험 전이다. 현재 동기화 데이터 장애가 발생했다는 보고가 아니다.
- 해당없음: 모델·계정·충돌·한도·이력 정리는 이미 Gate1의 선결 작업이며 지금 완료로 세지 않는다.
- 낮음: 사용자 채택 UI와 독립 sync 설정 저장 경계는 유지하되, 관리형 방향에 맞게 관련 문서/호출자를 연결해야 한다.

## 8. 근거

- [Core Data 미러링과 변경 이력](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer): 로컬 save/history와 import/export의 책임 경계.
- [Core Data 동기화의 일정·삭제 한계](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer): 자동 일정과 private/public DB 구분. local fetch를 네트워크 새로고침으로 오인하지 않음.
- [CloudKit 모델 제약](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit): 유일성 등 모델 제한.
- [여러 store와 CloudKit 구성](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit): 로딩할 store의 CloudKit 옵션. runtime OFF 완료 보장의 근거로 단정하지 않음.
- [persistent history 소비/정리](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users): export·소비와 정리 조건.
