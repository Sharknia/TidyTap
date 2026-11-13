# TidyTap 0.3.0 — Gate0 조사와 로컬 검증 계약

- 날짜: 2026-11-13, 개정 4
- 상위: [개발 계획](CLIPBOARD_PINBOARD_ICLOUD_PLAN.md), [UI 계약](CLIPBOARD_PINBOARD_UI_WORK_PLAN.md).
- 현재 사용자 지시: 별도 iCloud 시험 계정·보조 Mac을 준비할 수 없어 **로컬 검증까지만 진행**한다. 실제 동기화 관문과 이후 제품 통합은 보류한다.
- 이 문서는 Gate0-A 산출물이다. 작성·문서 검토는 실제 Core Data/CloudKit 적합성의 통과를 뜻하지 않는다.

## 1. 조사 결과와 실행 경계

| 항목 | 2026-11-13 확인 결과 | 의미 |
| --- | --- | --- |
| 개발 기기 | macOS 27.2(26B123), Xcode 27.2(27B52), arm64 | 이번 로컬 실행 환경. 최소 지원 OS의 수용 증거는 아님 |
| 제품 현행 | Xcode 앱/Helper 0.2.7(15), bundle ID `com.sharknia.TidyTap` / `.Helper` | 제품 버전 상향·저장소 변경은 통합 보류와 함께 미실행 |
| Developer ID | 키체인에 `Developer ID Application: HakKyeol Lee (V9SQZ6B7RP)` 유효 identity 확인 | CloudKit profile·capability·실행 성공과 별도 |
| 설치 제품 | `/Applications/TidyTap.app`에 embedded.provisionprofile 없음 | 현재 설치 앱을 CloudKit 시험 후보로 쓰지 않음 |
| 로컬 profile | 표준 MobileDevice/Xcode profile 디렉터리에서 TidyTap/CloudKit 관련 profile 찾지 못함 | 포털의 등록 상태와 구분한 로컬 조사 결과 |
| 개발자 포털 | 로그인된 팀 V9SQZ6B7RP의 App IDs·iCloud containers·Developer ID profiles를 읽기 전용 확인. TidyTap 및 tidy/probe 명칭의 관련 등록 없음 | 별도 App ID/container/profile 준비가 실제 연결의 선행 조건. 다른 앱의 컨테이너를 빌리지 않음 |
| cktool | 설치됨. get-teams는 management token 미설정으로 실패 | 앱의 iCloud 계정 로그인 여부를 뜻하지 않음. 토큰을 만들거나 출력하지 않음 |
| 두 Mac/시험 계정 | 사용자 답변으로 현재 확보 불가 | 실제 송수신·삭제 경합·OFF 종료 증거는 미실행으로 유지 |

포털 확인은 Aside의 이번 읽기 전용 세션 결과에 근거한다. 등록·프로파일 생성·다운로드·기존 컨테이너 변경·스키마 승격은 수행하지 않았다. 계정 이메일·비밀번호·토큰·프로파일 원문은 산출물에 넣지 않는다.

Developer ID 앱도 CloudKit과 push capability를 쓸 수 있으나 restricted entitlement에는 대응 profile이 필요하다. profile은 앱 bundle에 포함해야 하며, 현재의 독립 Helper 실행 파일에 entitlement만 붙이는 방식으로 해결하지 않는다. [Developer ID capability](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [TN3125 profile·독립 실행 파일](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

## 2. 이번 관문에서 허용할 작업

Gate0-A의 금붕어 검토 후 Gate0-B의 **로컬 부분**만 구현한다. 로컬 probe는 `NSPersistentContainer`만 사용하며 CloudKit container·계정·스키마 API를 생성/호출하지 않는다. 같은 SQLite/history의 재열기는 미러링 ON/OFF의 성공으로 세지 않는다.

| 실행 범위 | 허용·판정 |
| --- | --- |
| 합성 본문/서식/이미지의 로컬 저장·재조회 | 허용. 기존 콘텐츠 codec과 Core Data 저장 적합성만 확인 |
| 같은 store UUID로 unload/reopen, 삭제 history와 token 보존 | 허용. 실제 미러링 종료/재개와 별도 |
| 같은 실행 파일의 독립 writer 모드·두 프로세스 저장/알림/history | 허용. 실제 Helper 통합과 별도 |
| 기존 제품 데이터 읽기·이관·앱/Helper 실행/종료 | 하지 않음. probe는 생성된 전용 디렉터리만 사용 |
| 실제 CloudKit 연결·App ID/container/profile 생성·schema 초기화/승격 | 현재 보류. 잘못된 인자를 실제 연결로 대체하지 않음 |
| Gate1/P1~P4 제품 통합·제품 0.3.0 빌드·설치·출시 | 사용자 답변에 따라 보류 |

## 3. 생성 파일·모델·API

아래 파일만 생성한다. 기존 제품 소스·Xcode 프로젝트·설정은 수정하지 않는다. 산출물 업데이트는 이 문서와 실행 현황, 단계별 검토 보고서다.

| 작업 | 정확한 경로 | 책임 |
| --- | --- | --- |
| Create | `Spikes/ClipboardCloudKitProbe/ClipboardCloudKitProbe.xcodeproj/project.pbxproj` | 단일 macOS 앱 target, Swift 6, 최소 OS15.1, 로컬 엔진 패키지 참조, 외부 dependency 없음. Debug unsigned, 제품 버전0.3.0·probe build1 |
| Create | `Spikes/ClipboardCloudKitProbe/Sources/ProbeApp.swift` | CLI 파싱·가명 실행 ID·에러 코드 출력. self-test와 writer만 허용. 잘못된 인자는 저장소 열기 전 exit64 |
| Create | `Spikes/ClipboardCloudKitProbe/Sources/ProbeStore.swift` | 코드 모델·전용 SQLite·CRUD·history·token·load/unload. `NSPersistentContainer`만 사용 |
| Create | `Spikes/ClipboardCloudKitProbe/Sources/ProbeScenario.swift` | 아래 L01~L09 실제 assertion, 합성 fixture·두 프로세스 실행·권한 확인 |
| Create | `Spikes/ClipboardCloudKitProbe/Info.plist` | 실행 파일/버전/bundle 메타데이터와 LSUIElement. remote-notification 설정 없음 |
| Create | `Spikes/ClipboardCloudKitProbe/Probe.entitlements` | 빈 dict. iCloud·APS·application ID restricted entitlement 없음 |
| Create | `Spikes/ClipboardCloudKitProbe/README.md` | 로컬 실행·결과 경로·미실행 경계·정리 방법 |
| Create | `Scripts/run-clipboard-cloudkit-probe.sh` | no argument 또는 local만 허용. 전용 project 빌드 후 생성된 새 run 디렉터리에서 self-test 실행 |

생성 출력은 `build/clipboard-cloudkit-probe/` 안에 둔다. 빌드 cache는 `DerivedData`, 실행별 본문·SQLite·history token·결과는 새 `run.<임의값>` 디렉터리다. 재실행은 새 디렉터리이며 기존 실행/제품 파일을 삭제하지 않는다. 빌드 전에 재사용 DerivedData의 symlink와 해석 경로가 전용 출력 밖인 경우를 거부한다. source/model/API 변경이 이 경계를 넘으면 문서를 먼저 개정한다.

모델 식별자는 `ClipboardCloudKitProbe.v1`, 엔티티는 `ProbeEntry` 하나다. `id:UUID?`, `lastUsedAt:Date?`, `payload:Data?`, `isPinned:Bool`(false)을 갖고 유일성 제약·관계는 없다. id는 삭제 history에서 값 보존을 켠다. payload는 기존 `ClipboardCapturedContent`의 binary property list이며 external binary 저장을 허용한다. 생성 시 id/시각/payload를 반드시 채운다.

`ProbeStore`는 전용 `probe.sqlite`와 동일 모델을 사용한다. history tracking·remote-change notification 옵션을 켜고 cloudKitContainerOptions는 nil이다. 암묵 migration·mapping inference는 끈다. load 실패는 오류로 반환하며 새 빈 store로 바꾸지 않는다. context는 transactionAuthor를 `local-owner` 또는 `local-writer`로 구분하고 context queue 안에서만 접근한다. NSManagedObject/context를 프로세스 사이에 넘기지 않는다.

공개할 probe 내부 동작은 insert(content,id,at), snapshot(), setPinned(id,desired), delete(id), history(after:token), save/readHistoryToken, storeUUID(), objectURI(for:logicalID), close()다. snapshot은 id·시각·content·isPinned 값만 반환한다. insert는 현행 ClipboardHistoryEntry와 같은 id/copiedAt/content 봉투의 직렬화 크기10MiB를 검사한다. `ProbeStore.swift` 내부에 `ProbeEnvelope: Codable`을 두고 id:UUID·copiedAt:Date·content:ClipboardCapturedContent 및 같은 CodingKeys로 봉투를 만든다. 제품 ClipboardHistoryEntry는 public init이 없으므로 생성하지 않는다. 봉투를 binary property list로 인코딩한 뒤 제품 ClipboardHistoryEntry로 decode하여 세 값의 일치를 검사한다. 이 단일 isPinned 모델을 제품 고정/일반 소속 설계로 채택하지 않는다.

CLI `self-test <새 빈 root>`는 폴더의 symlink와 기존 내용을 거부하고 새 실행 marker/UUID를 만든다. `writer <root> <실행 UUID> <항목 UUID>`는 동일 marker·사용자 소유·제한된 권한·허용된 SQLite 위치를 확인한 뒤 합성 writer 항목 하나만 추가한다. marker 없는 임의 기존 SQLite나 제품 경로는 열지 않는다. CloudKit 모드와 알 수 없는 CLI 인자는 저장소를 열기 전에 exit64로 거부한다. 연결용 환경 변수를 읽는 인터페이스 자체를 만들지 않으며 상속 환경을 CloudKit 구성으로 해석하지 않는다.

스크립트와 실행 파일 모두 umask077을 사용한다. 실행 디렉터리0700·일반 파일0600 수준을 SQLite/WAL/SHM·외부 binary·marker·token·진단에도 적용하고 검사한다. 로그는 run 별칭·시험 ID·유형·크기·개수·판정·오류 코드만 남긴다. 본문/내용 hash·계정 식별자·실제 clipboard는 읽거나 출력하지 않는다.

## 4. 로컬 실행 프로토콜과 assertion

각 사건은 새 실행 root의 합성 데이터로 시작한다. 결과는 `results.json`에 L별 passed/failed/not_run과 측정값을 기록하고, assertion 실패 시 process exit1이다. 전체 PASS는 아래 로컬 L 사건에만 적용된다. 테스트를 생략하면 passed로 세지 않는다. script의 빌드 제한은180초, 전체 로컬 실행 제한은90초, child writer 제한은15초다. 시간 초과 시 이번 probe 프로세스만 종료하고 실패/부분 결과를 남긴다.

| ID | 사전 상태·행동 순서 | 관찰·합격/실패 |
| --- | --- | --- |
| L01 형식 보존 | 고정 시각·새 UUID로 텍스트, RTF+HTML 텍스트, 프로그램에서 생성한 PNG/TIFF, 2MiB 합성 blob을 각각 저장 | 재조회 값이 원본과 byte 단위 동일. 항목 UUID/시각 유지. 실제 붙여넣기/이미지 표시 검증은 아님 |
| L02 같은 store 재열기 | UUID·본문·고정 값을 기록→context 저장/reset→store remove→컨테이너 참조 해제→같은 URL/model로 재열기, 3회 | 매회 store UUID와 값·history 유지. 원래 항목 수 보존. CloudKit OFF/ON으로 표기하지 않음 |
| L03 삭제·토큰 | 초기 insert save→전체 history에서 insert/ID 확인→마지막 transaction token 저장→고정 update save→delete save→close/reopen→token unarchive 후 history 조회 | 초기 insert는 token 저장 전 확인. 재열기 후 token 이후 history에는 update/delete와 보존 삭제 id가 있고 초기 insert는 없음. history purge 호출 없음 |
| L04 재개할 로컬 변경 | close/reopen 사이 합성 X insert·pin/unpin·기존 H delete 후 다시 열기 | X 현재 값·H 부재와 삭제 history 보존. 원격 Y와의 병합/삭제 우선 정책은 미실행 |
| L05 크기 경계 | 직렬화 봉투10MiB 정확 경계 합성 blob 저장, 1byte 초과 봉투 추가 시도 | 경계는 저장·재조회 성공, 초과는 itemTooLarge 및 항목 수 불변. 50MiB 공통/캐시 정책은 미검증 |
| L06 두 프로세스 | owner baseline insert/save→마지막 token 파일 보존·알림 observer 등록→같은 executable의 writer가 고정 시각1700000100의 합성 항목 save/종료→파일 token 이후 history 소비·ID 대응 objectURI와 값 재조회 | writer exit0, 동일 store UUID. token 이후 정확히 writer author/해당 ID의 insert 한 건이며 baseline 없음. 해당 transaction token의 알림 수신과 UUID·본문·시각·고정 상태의 예상 ProbeValue 일치 확인. 최대15초 child, 알림/재조회는 child 종료 뒤5초까지. 미수신은 통과시키지 않음 |
| L07 연결 격리 | 실제 타입 NSPersistentContainer, nil cloud options·빈 entitlement 확인. unsupported cloud mode/잘못된 인자 실행 | 실제 CloudKit API/미러링 store 생성 경로 없음. 잘못된 모드는 exit64·새 store 생성 없음. packet 단위 네트워크 부재 증명은 아님 |
| L08 실패 보존 | 합성 잘못된 SQLite 파일에 load 시도, 실패 전후 파일 byte 확인 | 오류 반환, 원본 파일 불변·새 빈 store fallback 없음. 실제 disk-full/계정 quota 장애와 구분 |
| L09 로컬 보호 | 생성·reopen·writer 후 결과를 저장하고 root 전체 lstat 검사. marker 없는 writer·잘못된 실행 UUID·잘못된 kind·symlink root 거부도 실행 | 사용자 소유, 디렉터리의 group/other 접근0·일반 파일 group/other 접근0. symlink·marker 불일치·기존 내용 있는 root는 쓰기 전 거부 |

child는 실제 제품 Helper를 실행하지 않는다. cross-process 알림 수신은 lock으로 보호한 token 목록/카운터로 관찰하고, 값은 history의 writer author/ID를 확인한 뒤 재조회한다. history token의 파일 보존과 동기화 export watermark는 다른 개념이다. 이번 로컬 시험은 token을 삭제/정리하지 않는다.

## 5. 실제 CloudKit 사건 — 모두 현재 미실행

다음 계약은 실제 시험 자원이 마련된 뒤 사용할 기준이다. 이번 실행에서 별도 테스트 계정이나 capability 없이 흉내 내어 통과시키지 않는다. 실제 SDK가 통제·관찰을 제공하지 않는 경계는 불명확한 성공으로 바꾸지 않는다.

공통 사전 조건은 전용 App ID/container/profile·동일 시험 iCloud 계정의 Mac A/B, 합성 run ID, 서명/환경/OS 검증이다. 전용 private DB/store UUID/합성 ID 영역을 기록하며 Core Data 내부 zone을 직접 수정하지 않는다. 최초 import/export는 각600초까지 관찰한다. 사건 시작은 해당 로컬 save 완료 시각이고, 재관찰은 수동으로 같은 합성 ID의 상태·event·정리된 진단을 기록하는 것뿐이다. 600초 안에 수렴하지 않으면 실패 원인이 확인된 경우 failed, 그렇지 않으면 partial이다. 영구 누락을 증명했다고 하지 않는다.

| 사건 | 순서·관찰·중단·판정 |
| --- | --- |
| M01 | A의 형식/경계 저장→A export event→B import·로컬 값/형식 비교. 두 기기 값 불일치는 failed, 사건 미수행은 not_run |
| M02 | A/B가 H 존재 확인→A 일반 H 삭제→B 삭제 확인. probe delete 전달만 판단하며 고정 보존 전체는 Gate1 이후. 고정 소속 결과를 임의 추론하지 않음 |
| M03 | 새 합성 항목의 최초 전송이 실제 서버 미도달임을 허용된 네트워크 제어/진단으로 확인→연결 복구→A export/B import 확인. 미도달 증거가 없으면 해당 경로 not_run |
| M04 | B가 A 생성의 서버 반영 확인→A의 ACK 영속화 전 경계에서 중단→B 삭제 반영→A 재실행. 재생성 시 failed. 공개 API/진단으로 ACK 경계를 구분할 수 없으면 정확 경로 not_run, 일반 재시작 결과만 별도 기록 |
| M05 | 생성/이미지 export 도중 삭제/중단·재시작 후 A/B 최종 부재 확인. 제어 가능한 변형별 반복. 실제 전송 중임을 확인하지 못하거나 SDK 내부 역순 경계를 통제 못하면 그 변형 not_run |
| M06 | 공유 H 확인→A OFF 완료→X insert/pin/unpin·H delete→B Y insert→A ON→X/Y 상태·H 부재 확인. 제품 만료/충돌 전체는 Gate1 이후. 계정 귀속 불명 데이터 자동 반입 금지 |
| M07 | active import/export 상태에서 OFF 요청→로컬 save 직렬화/flush·context reset·store remove·old container/context 참조 해제→same UUID local-only reopen. 실제 종료 진단과 이후 새 local commit의 미전송 증거를 확인한 뒤에만 OFF 완료 인정. 120초 동안 신규 합성 변경이 B에 없다는 관찰만으로 ‘새 송수신0’을 보장하지 않음. 공개 근거/종료 증거 불충분이면 candidate partial·OFF 미검증이며 Gate0 합격 금지. rapid ON/OFF는 마지막 generation만 완료 |
| M08 | OFF에서 삭제·history/token 확인→same store ON→B 삭제 확인. export/소비 전 history 정리 없음. UUID/이력 손실 또는 삭제 재생성은 failed |
| M12 | [상위 계획 4절의 실행 수명 기준안](CLIPBOARD_PINBOARD_ICLOUD_PLAN.md#4-검증-구조와-구현-경계)대로 창 닫기 유지·명시적 종료 후 재개·로그인/업데이트 뒤 재개와 실제 Helper writer를 확인. 현재 local writer 성공으로 대체하지 않음 |
| M15 | 일반 XCTest/smoke의 가짜 주입 누락·잘못된 suite/연결을 실행 전 거부. 실 CloudKit fallback이면 failed. 제품 경로 수용이므로 로컬 L07만으로 전체 통과 아님 |

OFF 전환 공개 API 후보는 context 작업 직렬화→save/reset→persistentStoreCoordinator.remove(store)→소유 context/container 참조 해제 후 비미러링 구성으로 같은 store를 여는 순서다. SDK에는 remove API가 있지만 이것만으로 진행 중 CloudKit 작업 취소·드레인 보장을 확인한 것은 아니다. [Apple의 store unload 예제](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [일정·container 수명 진단](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer). 첫 예제는 schema 초기화 뒤 다른 stack에 넘기는 사례이며 runtime OFF 보장으로 확대하지 않는다.

실제 연결 진단은 나중에 `build/clipboard-cloudkit-probe/run.<ID>/cloud-evidence/`의 가명 요약 JSON으로만 보관한다. raw unified log·계정 토큰·인증정보는 저장소/보고서에 복사하지 않는다. 예상치 못한 본문/계정 식별자가 포함된 진단은 저장 전에 제외한다. probe 결과/합성 store는 별도 사용자 삭제 요청 전까지 build 아래에 보존하며 자동 삭제는 하지 않는다.

## 6. 완료 판정과 보고

- Gate0-A: 조사 사실·미확인·정확한 local probe 계약을 문서화하고 금붕어 검토. 통과 범위는 로컬 probe 작성 준비뿐이다.
- Gate0-B 로컬: L01~L09 결과와 빌드/오류/관찰 증거를 기록한 뒤 금붕어 검토. Core Data 후보 채택은 아직 불가하다.
- 차단: 별도 계정·보조 Mac·전용 App ID/container/profile이 없어 실제 송수신 관문을 실행할 수 없다. 앞의 계정·기기 부재는 사용자 확인, 등록 부재는 포털 조사 결과다. 현재 로컬 검증을 막지는 않는다.
- 해당없음: 최종 고정/일반 모델·충돌·계정·한도·이관·제품 Helper 수용은 이미 후속 Gate1/P1~P4 작업이며 사용자 답변으로 보류다.
- 실제 CloudKit 관문이 미실행인 동안 Gate0 전체 합격·제품 통합·출시 준비 완료로 표시하지 않는다.

## 7. Gate0-B 로컬 실행 결과

2026-11-13 이 기기에서 unsigned Debug probe를 빌드·실행했다. 첫 실행에서 L01~L09가 통과했고, context closure의 Sendable 경고를 정리한 뒤 수정된 코드로 다시 빌드·실행해 같은 9개 assertion의 통과를 확인했다. 이 시점 빌드의 compiler warning/error는 없으며 Xcode의 scheme supported-platform 관련 진단 한 줄은 남는다. 실제 동기화 실패를 의미하는 로그는 아니다.

- 실행 산출물: `build/clipboard-cloudkit-probe/run.7457wku2/launcher-summary.json`, `local/results.json`, `build.log`, `probe.log`.
- [보존한 구조화 결과](reviews/clipboard-030-execution-2026-11-13/gate0-b-local/results.json), [실행 요약](reviews/clipboard-030-execution-2026-11-13/gate0-b-local/launcher-summary.json).
- L08은 잘못된 합성 SQLite에 대해 예상한 Core Data 오류259/SQLite26을 발생시키고 원본 보존을 검사하므로 probe.log의 해당 오류는 의도한 실패 주입이다.
- 잘못된 script mode `cloud`는 exit64이며 새 run/빌드를 만들지 않았다. 정상 경로는 실제 NSPersistentContainer와 nil cloud options를 사용했다.
- 초회 금붕어 검토에서 L06 token 이후 소비·전체 값, L09 marker 불일치 시험이 부족함을 확인했다. 위 통과 결과는 초회 구현의 결과이며 계약 전체의 완료 증거로 사용하지 않는다. 수정 후 재실행·재검토 결과를 아래에 추가한다. 실제 CloudKit M 사건·제품 통합·최소 지원 OS 수용은 전부 미실행이다.

### 보완 후 재실행

`build/clipboard-cloudkit-probe/run.oedrtn73/`에서 build/probe exit0과 L01~L09 passed를 확인했다. L06은 baseline token을 파일에 저장·재사용하고 그 이후 writer insert/author/논리 ID를 연결해 확인했다. 예상 본문·시각·고정 상태와 같고 해당 writer transaction token을 가진 알림도 수신했다. L09에는 잘못된 UUID/kind의 거부와 기존 marker/값·새 store 부재 검사를 추가했다.

DerivedData 경계 함수의 실제 구현을 분리 호출해 symlink/외부 해석 경로 거부·정상 내부 경로 허용을 확인했고 외부 대상은 변경되지 않았다. 이 부정 경로 시험에서는 xcodebuild를 호출하지 않았다. [경계 검사 증거](reviews/clipboard-030-execution-2026-11-13/gate0-b-local/path-boundary-check.json). 현재 보존 results/launcher-summary는 이 수정본 실행 결과다. 독립 재검토를 완료했다. codebase는 새 지적0건·로컬 완료 가능, readiness는 L04 전체 값 assertion 누락1건을 보고했다. 해당 assertion을 강화해 run.j7v51t1i에서 L01~L09를 다시 통과했다. 이 마지막 assertion 수정의 추가 독립 재검토는 하지 않았다. [단계 검토 기록](reviews/clipboard-030-execution-2026-11-13/gate0-b-local/review_report.md).

### 현재 완료 범위

- Gate0-A: 조사/계약·금붕어 초회3역할·보완 후 준비도 재검토 완료.
- Gate0-B 로컬: 합성 형식·같은 store 재열기·history/token·독립 writer·크기·권한/거부·실패 보존 시험9개 통과, 금붕어 초회3역할·재검토2역할과 지적 반영 완료. 마지막 L04 assertion 추가는 자체 재실행 확인이다.
- 최종 실행: `build/clipboard-cloudkit-probe/run.j7v51t1i/`. 보존 구조화 결과 링크는 최신 실행을 가리킨다.
- Gate0 전체: **아직 합격 아님**. 실제 CloudKit M 사건·ON/OFF·계정/두 Mac·최종 모델/제품 통합은 사용자 답변대로 보류다.
