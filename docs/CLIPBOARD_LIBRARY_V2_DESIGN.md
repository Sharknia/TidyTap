# TidyTap 0.3.0 — 제품 저장·동기화 구현 계약

- 날짜: 2026-11-13. 상태: Gate1 설계. 실제 두 Mac 검증을 기다리느라 구현을 멈추지 말라는 사용자 정정을 반영한다.
- [상위 범위](CLIPBOARD_PINBOARD_ICLOUD_PLAN.md), [UI 계약](CLIPBOARD_PINBOARD_UI_WORK_PLAN.md), [현황](CLIPBOARD_030_EXECUTION.md).
- Core Data 관리형 후보를 제품에 구현하되 실제 CloudKit 적합성·계정/서명·OFF 종료 검증은 미완료로 표시한다. 기본 동기화 의도는OFF다. 설치·실사용 데이터 이관·공개 출시는 하지 않는다.

## 1. 모델과 충돌 정책

`ClipboardLibraryStore`를 엔진 패키지에 추가하고 기존 파일 `ClipboardHistoryStore`는 이관 reader/기존 fixture 용도로 유지한다. 콘텐츠 codec은 기존 `ClipboardCapturedContent`, 반환 값은 `ClipboardHistoryEntry`를 재사용한다. 두 Core Data 엔티티 `LibraryHistory`, `LibraryPin`은 각각 `id:UUID?`, `payload:Data?`, `timestamp:Date?`를 가진다. 모두 optional, payload external binary 허용, 유일성/관계/Deny 규칙은 없다. 모델 식별자는 `TidyTapClipboardLibrary.v1`이다.

고정은 독립적인 본문 사본을 보유한다. 일반 기록과 고정의 원격 변경이 다른 순서로 도착하더라도 만료·삭제가 고정 본문을 잃게 하지 않기 위한 선택이다. UI snapshot에서는 같은 본문을 한 번만 제공한다. 물리적 본문 중복 비용을 명시하며 ‘본문은 DB에도 반드시 하나’라는 제약은 두지 않는다. Core Data의 비원자적 관계 변경에 의존하지 않는다.

논리 ID는 버전 prefix·종류 tag·nil/존재 byte·big-endian UInt64 길이·원본 bytes를 순서대로 넣은 SHA256의 앞16byte로 만든 UUID다. 텍스트 plain은 canonical Unicode로 정규화해 ID를 계산한다. RTF/HTML/image byte·유형은 ID에 포함한다. hash는 로그에 기록하지 않는다. 실제 원문 payload는 binary property list로 보존한다. 동일 콘텐츠의 두 기기 동시 복사/고정은 같은 논리 ID로 표시하되 Core Data 객체의 내부 ID는 별개일 수 있다.

최근 기록은 논리 ID별 최신 timestamp 하나로 표시한다. 고정은 같은 ID의 pin 객체가 하나라도 있으면 보존하고 최근 고정 시각 순으로 표시한다. 같은 timestamp는 UUID 문자열로 정렬한다. 새 로컬 복사/붙여넣기 시도는 기존 같은 ID의 일반 기록을 최신 시각으로 갱신하고, 원격 import는 사용 시각을 바꾸지 않는다.

일반 삭제는 현재 수신한 해당 ID의 History 객체만 지우고 Pin은 유지한다. 전체 삭제도 현재 수신한 모든 일반 기록을 지우며 고정·클립보드는 유지한다. 미수신 새 기록까지 초기화하는 전역 reset은 없다. 해제는 현재 수신한 Pin 객체를 모두 삭제한다. concurrent 새 pin/새 copy가 기존 삭제에 관측되지 않았다면 이후 보일 수 있다. 이미 수신한 동일 객체의 삭제/늦은 update 전달은 Core Data private DB 삭제 추적에 맡기며 재등장 방지의 실환경 검증은 남긴다. 프레임워크가 모든 충돌에서 사용자 의도의 ‘나중’을 판정한다고 주장하지 않는다.

일반 기록은7일·최대1,000개·직렬화 봉투 합계50MiB·항목10MiB다. 정리는 일반 기록만 대상으로 하며 pin 사본에 영향이 없다. 고정도 최대1,000개/50MiB 기준을 적용하되 초과 고정은 오류로 거부하고 기존 고정을 자동 삭제하지 않는다. 두 기준은 현재 수신한 라이브러리에 적용하는 공유 정책이며 디스크 전체 상한은 아니다. 고정 전용 항목 사용은 같은 ID의 일반 기록을 다시 만들고 고정은 유지한다. 해제만으로 일반 기록을 복원하지 않는다. 사건의 시각은 기존 copy/paste 시도 시각이며 기기 시계 오차는 실제 시험 항목이다.

## 2. 저장 API·프로세스·이관

엔진에 `ClipboardHistoryStoring` 프로토콜(add/recordOversizedCopy)을 두고 capture service가 store provider로 요청 시점의 저장소를 받도록 한다. 기존 init(store:)는 같은 인스턴스를 반환하는 경로로 유지한다. 운영 Helper의 provider는 캡처마다 현재 계정 namespace로 새 로컬 handle을 받는다. 앱 UI 요청은 표시 시점 handle을 유지해 늦은 요청이 다른 계정에 쓰지 못하게 한다.

`ClipboardLibraryStore`는 MainActor, 같은 프로세스 안의 Core Data context queue에서 동작한다. 일반 writer는 항상 `NSPersistentContainer`·history/remote-change 옵션ON·cloud options nil이다. process별 transactionAuthor를 지정한다. v1에서는 persistent history를 임의 purge하지 않는다. UI/Helper는 NSManagedObject를 전달하지 않는다.

API: init(directory:retention:maximumEntries:maximumBytes:maximumItemBytes:), add(_:copiedAt:), promote(_:at:), entries(now:), entry(id:now:), snapshot(now:), setPinned(_:pinned:at:), delete(_:), deleteAll(), recordOversizedCopy(changeCount:), oversizedCopyChangeCount(). `snapshot`은 entries/historyOrder/pinnedOrder 값을 반환한다. delete는 일반 소속 제거다. `.entry`는 고정 전용 ID도 읽는다. set-pinned는 원하는 Bool이며 반복 입력은 중복을 만들지 않는다.

Application Support/도메인/clipboard-library-v2/<namespace>/library.sqlite를 사용한다. namespace는 처음 `local`, 계정 연결 후 CK user record name의 SHA256 hex이며 raw 계정명은 기록하지 않는다. 앱/Helper의 현재 namespace는 독립 preferences 키로 공유한다. OFF에서도 bound namespace의 로컬 사용을 유지한다. 처음 ON일 때만 미귀속 local store의 값을 첫 계정으로 반입한다. A→B는 fresh B store를 열고 A 내용은 반입하지 않는다. OFF 중 계정 변경은 ON의 계정 확인 시점에 반영한다. 다시 A가 되면 기존 A store를 사용한다.

구 .clip 이관은 처음 local namespace를 열 때만 전용 migration lock과 기존 store.lock 아래에서 지원 파일을 읽어 검증 후 단일 Core Data save로 반입한다. 원본을 변경/삭제하지 않는다. 완료 marker는 save 뒤 원자적으로 기록한다. crash 재시도는 논리 ID/최신 timestamp로 멱등 처리한다. 완료 뒤 구버전 파일을 자동 재반입하지 않아 다운그레이드/재업그레이드가 삭제 내용을 부활시키지 않는다. 구버전에서 이후 생긴 복사는 별도 원본에 남으며 자동 합병하지 않는다. 실제 설치 교체의 기존 Helper 종료/잠금은 현행 업데이트 경로를 유지하고 실기기 수용은 미실행이다.

라이브러리/namespace/migration marker·oversize marker·SQLite/WAL/SHM/외부 binary는 사용자 전용 권한이다. secure parent0700·일반 파일0600 수준을 검사/보정하며 symlink store/marker를 거부한다. load/이관 오류 시 빈 store fallback이나 원본 삭제를 하지 않는다. 기존 검색어/본문/hash 진단 기록은 제거하고 이관 시작 전 구 로그를 정리한다.

## 3. 동기화 엔진과 설정

Main app이 유일한 미러링 소유자다. 동일 모델·SQLite를 `NSPersistentCloudKitContainer`로 열고 private DB를 사용한다. Helper는 로컬 writer다. 창 닫기는 소유자를 자동 종료하지 않고, 명시적⌘Q 후에는 다음 앱 실행에서 저장된ON으로 재개한다. 실제 앱 종료 중 이미 수락된 작업 취소는 보장하지 않는다.

독립 sync Bool의 read/write를 preferences protocol/실 store/fake에 추가한다. 입력 Codable snapshot·request ID·apply status·로그인 항목을 바꾸지 않는다. sync delegate→별도 Coordinator save→실행 Coordinator apply 순서다. 저장 실패만 의도를 되돌린다. 적용 실패는 저장 의도와 별도 상태다. 각 요청 generation을 확인해 늦은 ON/계정 결과가 OFF를 뒤집지 못한다.

실행 Coordinator는 계정 조회 provider와 mirroring transport를 주입받는다. 실제 provider는 CKContainer 계정 상태/사용자 record ID를 조회하며 XCTest/launch-smoke에는 주입된 fake만 사용한다. `XCTestConfigurationFilePath`/테스트 실행·일반 smoke에서는 실제 transport를 만들지 않는다. 앱 Info의 container ID, 서명 entitlement/container 일치와 embedded profile이 없으면 명시적인 구성 오류를 표시하고 네트워크 연결을 시도하지 않는다. 기본 build는 이런 서명 자원이 없어도 빌드/로컬 사용은 가능하다.

OFF 구현 후보는 신규 apply 차단→미러링 context save/reset→persistent store remove→container 참조 해제다. 이전 container의 해제가 확인되지 않았거나 active event가 남으면 ‘끄는 중’으로 유지하며 timeout을 성공으로 바꾸지 않는다. 마지막 generation의 종료가 확인됐을 때 로컬 전용 상태를 표시한다. 실제 CloudKit 내부 종료/전송 부재는 여전히 미검증이다. ON은 same store/history를 사용하며 자체 데이터 합집합·전체 재업로드·zone 조작은 하지 않는다.

sync 상태는 off/starting/syncing/pausing/waitingAccount/configurationError/failed다. 단순 export event를 ‘모든 기기 최신’으로 표시하지 않는다. 자동 schedule을 쓰고 일반 fetch를 강제 네트워크 새로고침으로 표시하지 않는다. retry는 저장된ON의 계정 재확인/연결 복구와 저장된OFF의 종료 확인 재시도다. OFF 재시도가 ON을 켜지 않는다.

프로젝트에 설정용 entitlements와 container ID build setting/Info key를 준비한다. 실제 profile/App ID/container 생성·Production schema 승격·공개 배포는 별도 자원/실행 관문이며 구현을 막지 않는다. release package는 sync 구성 부재/오일치가 있으면 동기화 가능 후보로 통과하지 않게 검사한다.

## 4. 파일 경계와 단계별 시험

| 단계 | Create | Modify |
| --- | --- | --- |
| P1 | `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardLibraryStore.swift`, `Packages/TidyTapInputEngine/Tests/TidyTapInputEngineTests/ClipboardLibraryStoreTests.swift` | ClipboardCaptureService.swift, ClipboardHistoryStore.swift(프로토콜 conformance만), Sources/Shared/TidyTapProduct.swift, Sources/Helper/InputFeatureAdapters.swift, FinderFeedbackAppHost.swift, HelperRuntime.swift, Sources/App/AppDelegate.swift 및 관련 엔진/앱 fixture |
| P2 | 없음 | Sources/App/ClipboardHistoryPanelController.swift, AppDelegate.swift, Sources/Shared/Localizable.xcstrings, Tests/TidyTapTests/SettingsViewControllerTests.swift, TidyTapSettingsTests.swift, SettingsSnapshotRenderer.swift |
| P3 | `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardLibraryMirror.swift`, `Sources/App/ClipboardSyncCoordinator.swift`, `Tests/TidyTapTests/ClipboardSyncCoordinatorTests.swift`, `Config/TidyTap.entitlements` | Sources/Shared/TidyTapSettings.swift, TidyTapIPC.swift, Sources/App/SettingsCoordinator.swift, SettingsViewController.swift, AppDelegate.swift, Sources/Helper/InputFeatureAdapters.swift, TidyTap.xcodeproj/project.pbxproj, Resources/AppInfo.plist, 관련 tests/fake·Localizable |
| P4 | 없음 | Scripts/verify-release-build-settings.sh, verify-release-artifact.sh, package-preview-dmg.sh, package-release-dmg.sh, test-clipboard-history-gates.sh, 문서/README·URS·수용 현황·프로젝트 마케팅버전0.3.0 |

P1 시험: 로컬 재열기/두handle 쓰기·종류별codec·고정 전용사용·해제시비복원·삭제/전체삭제고정보존·TTL/한도·초과고정오류·논리ID/중복·단일save이관/재실행/불량원본보존·권한/계정store격리. P2는 UI 계약의 세션·검색·선택·⌘1/⌘2·IME·비동기변경과 한/영 fixture를 검증한다. P3는 fake로 ON/OFF generation·저장/적용실패·첫계정반입/A→B비반입·재시도·시험격리를 검증하고 실제 transport는 빌드한다. P4는 엔진 suite·앱 XCTest·unsigned build·가능한 renderer/기존 gates·릴리즈구성 검사를 실행한다.

각 단계 산출물과 검사 뒤 새 맥락의 금붕어 검토를 진행하고 지적을 보완한다. 실제 두 Mac·서명한 CloudKit·실제 한글/대상앱 삽입·지원 OS 시험 미실행과 제품 코드 구현 완료를 구분한다. 기존 probe의 통과를 실제 동기화 통과로 승격하지 않는다.

## 5. Gate1 금붕어 보완 — 구현에 적용할 최종 규칙

앞 절의 첫 계정 ‘반입’ 방식은 아래 **원자적 귀속**으로 대체한다. `ClipboardLibraryRouter`를 ClipboardLibraryStore.swift 안에 두고 모든 로컬 쓰기는 root의 routing.lock 아래 namespace 해석→store open→save 순서로 실행한다. routing.json은 active folder·계정별 folder mapping·generation을 한 번에 원자적으로 쓴다. 최초 연결은 기존 local 폴더를 A 소유로 지정하고 SQLite를 복사/이동하지 않는다. 캡처도 같은 lock으로 현재 route를 해석하므로 연결 전후 항목이 같은 store에 남는다. A→B는 새 B 폴더, A로 돌아오면 이전 A mapping을 사용한다. 실패 시 이전 routing.json을 유지하며 데이터는 그대로다. namespace/generation은 preferences가 아니라 이 단일 파일이 권위다.

UI/Helper 최신 조회는 저장 전 dirty 상태가 없는 새 context/handle에서 수행한다. AppDelegate는 Core Data remote-change를 관측하고 현재 계정/표시 세션의 snapshot을 다시 읽어 기존 공통 갱신으로 전달한다. Helper의 기존 분산 알림도 같은 경로다. 매번 새로 읽으므로 앱 자체 history token 소비/merge는 추가하지 않으며 미러링 history는 purge하지 않는다. 두 handle의 add/delete 뒤 기존 query handle의 전체 snapshot을 확인하는 시험을 넣는다.

구 .clip reader는 ClipboardHistoryStore.entries를 호출하지 않는다. Router가 기존 store.lock을 잡고 Data/PropertyListDecoder로 비파괴 decode하며 불량 파일이 하나라도 있으면 이관 오류다. 원본 bytes·경로는 그대로다. v2 단일 save와 완료 marker로 멱등 반입하며 실패 전후 원본 파일 동일성을 시험한다.

고정 한도는 논리 ID별 본문 직렬화 합계다. 원격/별도 writer에서 합쳐져 초과한 고정도 모두 보존한다. 초과 상태에서는 새로운 ID의 로컬 고정만 거부하며 기존 ID set-pinned(true)는 멱등 성공한다. 두 묶음 병합 초과 시험을 넣는다.

붙여넣기 IPC에도 route folder/generation을 포함한다. Helper는 조회 직전과 실제 clipboard write 직전에 현재 route와 비교해 불일치면 기존 세션을 거부한다. 계정 전환 중 이미 대기하던 요청이 새 계정에 재조회/갱신되지 않게 한다. 이 연결은 Sources/Shared/TidyTapIPC.swift·Sources/App/AppDelegate.swift·Sources/Helper/FinderFeedbackAppHost.swift 및 TidyTapSettingsTests.swift에 적용한다.

정확한 기존 시험 수정 경계는 Packages/TidyTapInputEngine/Tests/TidyTapInputEngineTests/ClipboardCaptureServiceTests.swift, Tests/TidyTapTests/TidyTapSettingsTests.swift, Tests/TidyTapTests/SettingsViewControllerTests.swift, Tests/TidyTapTests/SettingsSnapshotRenderer.swift, Tests/TidyTapTests/HelperLauncherTests.swift다. 문서 수정은 docs/CLIPBOARD_HISTORY_URS.md, docs/CLIPBOARD_HISTORY_ACCEPTANCE_STATUS.md, docs/CLIPBOARD_PINBOARD_ICLOUD_PLAN.md, docs/CLIPBOARD_PINBOARD_UI_WORK_PLAN.md, docs/CLIPBOARD_030_EXECUTION.md, README.md, README.ko.md다. 표의 생략된 Helper/App 파일명은 각각 Sources/Helper/와 Sources/App/ 아래 경로다.

P1 구현 보완: payload는 기존 ClipboardHistoryEntry binary 봉투로 보존하며 Pin의 timestamp는고정순서, payload.copiedAt는원본사용시각이다. 메타데이터 임시파일은0600설정/fsync뒤rename하고publish뒤실패가능작업을두지않는다. P3계정전환호출자가생기기전에붙여넣기route/generation과remote-changeUI연결을완료한다.

P4 생성파일 추가: Scripts/verify-clipboard-cloudkit-configuration.py. Release 파이프라인은 실제 앱의 container/서명entitlement/embedded profile metadata/팀/만료/APNs를 검증하며 미설정 후보를 CloudKit release로 통과시키지 않는다. Preview와 unsigned 로컬시험은 이와 구분한다. 구조화 XCTest summary도 단계 증거로 보존한다.

P4 smoke 보완: 기존 입력/권한/Finder-ready IPC도 LaunchSmoke의 suite object를 사용하도록 HelperLifecycle.swift와 앱/Helper 관측자를 연결한다. production object는 그대로 유지한다. 이전 기동 검사에서 HID/단축키 매핑은 불변이었으나 production preferences hash가 달라져 이 시험 경로를 분리했다. 실제 설정 값은 추정해 되돌리지 않으며 격리 후 전체 기동 검사를 다시 수행한다.

P4 회귀시험 생성 경계: Scripts/test-clipboard-cloudkit-configuration.py. 표준 unittest로 합성 서명 metadata 정상·container/팀/App ID/APNs/만료/환경 불일치·preview와 release 거부 조건을 재실행한다.

P4 기존 Scripts/test-release-dmg-workflow.sh도 새 CloudKit gate의 공개 산출물 게시 전 위치를 검사하고 위 Python 회귀시험을 호출한다.
