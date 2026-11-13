# 5단계: 전체 방향·대안 검토

두 독립 검토 완료. 새 지적 Z01(Major·중간): 최종 CloudKit schema 초기화와 Production 승격 관문 명시. 나머지는 예정된 Gate 확인.


---

# 5단계 Zoom-out 독립 검토 원시 결과

- 검토 상태: 완료
- 대상: `docs/CLIPBOARD_PINBOARD_ICLOUD_PLAN.md` 개정 0.3 전체(1~157행)
- 검토 관점: 주인님이 확정한 보관함 1개·전체 히스토리·OFF 일시중지/ON 병합을 유지하면서, 관리형 후보를 먼저 시험하는 계획의 단순성·재사용·구조적 막다른 길을 점검했다.
- 결론: 조사·검증 계획으로 진행 가능하다. 새 Blocker 0건, Major 1건, Nit 0건. 아래 Major는 제품 장애가 아니라 실제 Production 연결 전에 작업 순서에 명시할 누락이다. 관리형 후보의 채택이나 실기기 통과를 선언하는 결과가 아니다.
- 격리: 과거 보고서·대화·메모리는 조회하지 않았다. 지정된 UI 문서에 포함된 과거 검토에 대한 설명은 원문 문맥으로 읽었으나 연결된 과거 보고서는 열지 않았고 판단 근거로 사용하지 않았다.

## 새 지적

### Z01. 최종 제품 모델의 CloudKit schema 초기화·Production 승격을 작업 관문에 명시해야 한다

- 원문 EGM 등급: **Major**
- 사용자 등급: **중간**. 현재는 파일 기반 제품이며 조사·검증 계획 작성 목표를 막지 않는다. 실제 Production 연결 전에 보완할 작업 순서다. 실제 schema 배포 여부는 **미확인**이며, 지금 배포가 실패했다고 주장하지 않는다.
- 위치: 대상 64~66행(probe 모델), 97행(최종 제품 Production 설정 검증), 105~111행(Gate0-A~P4), 145~147행(Gate0/Gate1 산출물).
- 근거: Gate0는 `ProbeEntry`를 사용하고 최종 제품 schema는 확정하지 않는다. Gate1은 최종 schema/API를 확정하며 P4는 최종 후보의 Production 연결을 확인하지만, 최종 모델로 개발 schema를 초기화하고 검토한 뒤 Production으로 승격하는 작업과 책임 단계가 없다. 제공된 `sources/history-consumption.md`의 “Create the CloudKit schema”는 Production에서 record type/field를 자동 생성하지 못하고 schema 배포 없이는 서버와 통신하지 못한다고 설명한다. `sources/model-limits.md`의 “Promote the Schema to Production”은 승격한 type/field를 제거·수정할 수 없다고 명시한다.
- 단순성·구조적 이유: probe가 시험한 schema와 최종 모델의 schema를 구분한 방향은 옳다. 다만 최종 모델의 Production 준비를 ‘설정 확인’만으로 읽으면 연결 시험에서 뒤늦게 schema 누락을 발견하거나 probe용 type을 최종 컨테이너에 영구 반영할 수 있다. 전자는 검증 재작업, 후자는 되돌릴 수 없는 schema 잔여물을 만든다. 이 위험은 별도 schema 프레임워크를 만들어 해결할 문제가 아니라 기존 관문에 필수 선행 작업을 적으면 된다.
- 최소 개선: Gate1 산출물에 “최종 모델의 개발 schema 초기화·검토 방법 및 probe type과의 분리”를 넣고, P3 또는 P4의 최초 Production 연결 직전에 “검토된 최종 schema 승격 완료”를 통과 조건으로 한 줄 추가한다. `initializeCloudKitSchema`는 명시적 개발용 경로에만 두고 정상 실행·Production에서 호출하지 않는다고 적는다. 현재 단계에서 실제 초기화나 승격을 실행할 필요는 없다.

## 이미 계획된 선결 작업 — 새 결함으로 계산하지 않음

### Z02. OFF/ON의 같은 store 보존과 미러링 소유자의 수명 검증

- 원문 EGM 등급: **판정 대상 아님(기존 선결 작업)**
- 사용자 등급: **해당없음**. 실제 적합성은 **미확인**이다.
- 위치·근거: 대상 64~75행, M06~08·M12, 143~145행에 정상 종료/재연결·store UUID·이력 보존·두 프로세스·주앱 수명 검증이 명시돼 있다. `sources/coredata-limits.md`의 “Avoid synchronizing a store with multiple persistent containers”가 지적하는 중복 소유자 문제를 단일 소유자로 제한하고 있다.
- 최소 개선: 별도 개선 없음. Gate0 결과로 공개 API와 관찰 범위를 기록하면 된다. 주앱 소유의 실패를 확인하기 전에 신규 상주 서비스나 두 번째 미러링 엔진을 추가할 이유는 없다.

### Z03. 고정/일반 수명·중복·삭제·한도·계정 정책 미확정

- 원문 EGM 등급: **판정 대상 아님(기존 선결 작업)**
- 사용자 등급: **해당없음**. 제품 모델과 사건별 최종값은 **미확인**이다.
- 위치·근거: 대상 23행, 41~56행, Gate1, M09~14, 147행이 Gate1 완료 후 제품 구현으로 진행하도록 막고 있다. 단일 probe 모델이 최종 소속·충돌 정책을 검증한다고 하지도 않는다. 이 미정 상태를 검증 우선 계획의 현재 결함으로 재등록하지 않았다.
- 최소 개선: 별도 개선 없음. Gate1 사건표를 작성할 때 결정하면 된다. 이 검토에서 승자 규칙·분산 카운터·세대 초기화·영구 감사 로그를 임의로 추가하지 않는다.

### Z04. 기존 지원 형식·UI·설정 경로 재사용

- 원문 EGM 등급: **판정 대상 아님(재사용 확인)**
- 사용자 등급: **해당없음**.
- 위치·근거: 대상 65행은 기존 `ClipboardCapturedContent` 직렬화를 사용하며 81행은 독립 scalar preferences 경로를 유지한다. 코드 검색에서 `ClipboardCapturedContent`는 이미 `Codable, Hashable`이고 text/RTF/HTML 및 PNG/TIFF를 표현한다. 기존 `ClipboardHistoryStore`는 `.clip` 파일·flock·prune에 의존하고 `ClipboardCaptureService`가 이 구체 타입을 사용한다. 저장 계층·수집·호출자 변경은 P1/P3 및 Gate1의 API 계약에 포함돼 있다. 기존 Core Data/미러링 구현은 지정한 제품 소스 검색에서 발견되지 않았다.
- 최소 개선: 별도 개선 없음. `ClipboardCapturedContent`·기존 UI를 재사용하고 저장 방식만 Gate1 계약에 맞게 연결하는 현재 경계를 유지한다. 파일 기반 저장소 자체를 미러링 엔진으로 재사용하라는 요구는 새로운 전송·삭제 프로토콜을 만들게 하므로 더 단순하다고 볼 근거가 없다.

## 기준별 판단

| 기준 | 판단 |
| --- | --- |
| 목적·맥락 충분성 | 충족. 무엇을 동기화하며 OFF가 무엇인지, 이번 범위와 제외 범위가 명확하다. |
| 근본 문제 집중 | 충족. 파일 이동으로 동기화 문제를 덮지 않고 로컬 저장·변경 이력·import/export를 함께 검증한다. |
| YAGNI | 새 위반 없음. 서버·패키지·이중 엔진·직접 감사 프로토콜·세대 초기화를 추가하지 않는다. |
| 데이터 흐름·경계 | 조사 단계에 적절하다. 단일 미러링 소유자와 UI 값 snapshot을 두며 실제 소유자·API는 관문 뒤에서 확정한다. |
| 고도 유지 | 충족. probe 속성·파일 목록은 시험 재현성과 격리를 위한 구체성이다. 제품의 상세 구현을 미리 늘린 것으로 보지 않는다. |
| 플랫폼·코드 재사용 | 적절. Core Data/CloudKit와 기존 콘텐츠 표현을 사용한다. Z01의 schema 수명주기는 작업 표에 명시가 필요하다. |
| 실제 검증 주장 | 적절. 미실행·관찰 한계·probe/제품 수용을 분리한다. |

## 실제로 읽은 파일

전체 본문을 읽은 파일:

1. `/Users/crobat/.codex/plugins/cache/egm/egm/0.1.1/agents/zoom_out.md`
2. `/Users/crobat/.codex/plugins/cache/egm/egm/0.1.1/resources/document_standards/zoom-out-standard.md`
3. `docs/reviews/clipboard-managed-sync-2026-11-13/manifest.json`
4. `docs/CLIPBOARD_PINBOARD_ICLOUD_PLAN.md`
5. `docs/CLIPBOARD_PINBOARD_UI_WORK_PLAN.md`
6. `docs/CLIPBOARD_HISTORY_URS.md`
7. `docs/reviews/clipboard-managed-sync-2026-11-13/sources/coredata-sync.md`
8. `docs/reviews/clipboard-managed-sync-2026-11-13/sources/coredata-limits.md`
9. `docs/reviews/clipboard-managed-sync-2026-11-13/sources/model-limits.md`
10. `docs/reviews/clipboard-managed-sync-2026-11-13/sources/store-configuration.md`
11. `docs/reviews/clipboard-managed-sync-2026-11-13/sources/history-consumption.md`
12. `README.md`
13. `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardHistoryStore.swift`
14. `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardPasteboardReader.swift`
15. `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardCaptureService.swift`
16. `Spikes/CapsLockProbe/Package.swift`
17. `Spikes/FinderCutPasteProbe/README.md`

일부 본문·검색 일치 문맥을 읽은 파일:

- `Sources/App/AppDelegate.swift`
- `Sources/Helper/HelperRuntime.swift`
- `Sources/Helper/InputFeatureAdapters.swift`
- `Sources/Helper/FinderFeedbackAppHost.swift`
- `Sources/Helper/ApplyCoordinator.swift`
- `Sources/Shared/TidyTapProduct.swift`
- `Sources/Shared/TidyTapSettings.swift`
- `Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/ClipboardPasteboardWriter.swift`

검색 범위: `Packages/TidyTapInputEngine/Sources`, `Sources/App`, `Sources/Helper`, `Sources/Shared`에서 콘텐츠·저장소·Core Data 관련 선언/호출자를 검색했다. `Spikes`·`Scripts`는 파일 목록도 확인했다. 검색 결과를 전체 구현 감사로 확대 해석하지 않았다.

실제 제품 시험·빌드·클라우드 연결·코드 수정은 하지 않았다. 이 파일만 작성했다. 남은 위험은 Gate0/Gate1의 미확인 적합성과 Z01의 최종 schema 준비 순서다.

---

# EGM 5단계 Inventive Catalyst 독립 검토 원시 결과

- 대상: `docs/CLIPBOARD_PINBOARD_ICLOUD_PLAN.md` 개정 0.3 전체(1~157행)
- 모드: REVIEW, 전략·구조 수준
- 완료: 2026-11-13. 지정된 대상·local_context·source_context를 모두 읽고 검토 완료.
- 결과: **No false compromise detected**. 새 결함 지적 0건(Major 0, Nit 0). 아래 V01~V03은 이미 계획된 관문의 확인 및 대안 평가이며 새 결함이 아니다.
- 주인님이 확정한 전체 히스토리 동기화·OFF 일시중지·ON 병합을 전제로 평가했다. 제품 코드와 실환경 동작을 검증했다는 뜻은 아니다.

## V01 — 로컬 반응성과 동기화 신뢰성을 맞바꾸는 구조는 발견하지 못함

- EGM 원등급: 없음(지적 아님). 사용자 등급: **해당없음**. 실제 API 적합성은 **미확인**이며 이미 Gate0 관문이다.
- 위치: 대상 12~16, 64~79, 105~107, 139~145행.
- 근거: 로컬 save/history와 비동기 import/export를 분리하고 단일 미러링 소유자를 둔다. 영구 삭제 감사 로그·생성 수신증·두 번째 전송 엔진을 선행 도입하지 않는다. 제공된 TN3163의 `The synchronization in a nutshell`은 로컬 저장·persistent history·후속 export/import의 책임 분리를 설명한다. TN3164의 `Avoid synchronizing a store with multiple persistent containers`는 동일 store의 복수 미러링 충돌과 단일 담당 앱 방향을 설명한다.
- 최소 구조/개선: 현재의 관리형 후보 우선 검증을 유지한다. 같은 모델·SQLite store를 사용하는 단일 미러링 소유자와 로컬 writer probe로 재개·삭제·두 프로세스 경계를 먼저 확인하면 된다. Gate0 결과 전에는 별도 동기화 coordinator 계층·작업 큐·영구 수신증 프로토콜을 추가할 근거가 없다.
- 패턴: Extraction/Intermediary를 이미 플랫폼이 제공한다. 앱의 수집·조회와 원격 전송을 프레임워크의 로컬 store/history를 통해 분리한다.
- 부수 비용: 파일 저장에서 Core Data로의 이관, history 소비, 모델 제약, 소유자 수명·서명 구성이 필요하다. 관리형을 선택한다고 제품의 고정/삭제/중복 정책까지 사라지지는 않는다. 이 비용을 문서가 Gate0/Gate1/P1에 명시했다.
- 반론 검토: 기존 파일을 그대로 유지하면 이관은 줄지만 직접 업로드 상태·삭제·재전송·OFF 재개를 구현해야 한다. 현재 자료로 총구현량이 더 작다고 입증할 수 없다. 따라서 관리형 후보를 시험하기 전 대안으로 전환할 이유가 없다.

## V02 — 즉시 OFF와 로컬 수집 지속의 긴장은 숨긴 타협이 아니라 명시된 검증 관문

- EGM 원등급: 없음(지적 아님). 사용자 등급: **해당없음**. 같은 store 재로딩으로 약속을 달성할지는 **미확인**.
- 위치: 대상 29~39, 71~75, 127~129, 139~145행.
- 근거: OFF 요청·끄는 중·꺼짐 완료를 구분하고, Bool 변경을 종료 증거로 쓰지 않는다. 같은 store UUID/history를 유지한 비미러링 전환과 재연결을 후보로 삼되 실패하면 합격시키지 않는다. TN3164는 기존 container에 묶인 객체가 남으면 container 교체만으로 기존 인스턴스가 해제되지 않을 수 있다고 설명한다. 제공된 store-configuration 문서는 로드 시 구성을 보여줄 뿐 런타임 즉시 중단을 보장하지 않는다. 대상은 이 근거의 한계도 명시했다.
- 최소 구조/개선: 예정된 Gate0에서 동일 store 보존·송수신 차단·writer 요청 직렬화를 검증한다. 문서 밖의 공개 API 중단 보장을 가정하거나 프로세스 강제 종료를 표준 경로로 추가하지 않는다.
- 대안 및 반론: 별도 영구 local-only store를 만들면 OFF 중 연결 분리는 쉬워질 수 있으나 ON에서 항목/삭제를 두 store 사이로 이동·병합하는 추가 프로토콜이 필요하다. 영구 local-only 모드는 사용자 확정 의미와도 다르다. 현 단계의 최소 대안으로 채택할 근거가 없다.
- 부수 비용: 현재 후보도 전환 중 저장 요청 직렬화와 늦은 완료 무효화가 필요하다. 실패 시 ‘끄는 중/오류’를 유지하는 복구 경험이 생긴다. 대상 75행과 UI 계획이 이미 담당한다.

## V03 — 고정 보존·일반 만료·중복 제거를 하나의 삭제 동작에 결합하지 않음

- EGM 원등급: 없음(지적 아님). 사용자 등급: **해당없음**. 최종 모델·사건별 승자는 **미확인**, Gate1 선결 설계.
- 위치: 대상 45~56, 65, 79, 107, 130~132, 145행; UI 계획 `데이터 경계`.
- 근거: 고정의 수명과 일반 기록 소속을 분리하고, UI는 본문 하나와 두 소속/순서 배열의 값 snapshot을 받는다. 로컬 캐시 퇴출을 mirrored delete와 동일시하지 않고, 단일 probe Bool로 제품의 모든 충돌을 입증하지 않는다. model-limits는 유일성 제약 미지원·관계 비원자성을 설명하고, history-consumption의 `Remove duplicate data`는 모든 peer가 같은 항목을 보존하는 결정적 중복 처리와 즉시 삭제의 주의를 설명한다.
- 최소 구조/개선: Gate1에서 한 논리 항목의 본문과 일반/고정 소속을 표현하는 최소 모델을 사건표로 고른다. 지금 별도 보관함 엔진·본문 중복 저장소·범용 CRDT·영구 이벤트 저널을 요구하지 않는다.
- 패턴: Segmentation을 데이터 수명/소속의 책임 구분에 적용하는 현재 방향은 적절하다. 실제 엔티티를 몇 개로 분리할지는 검증 결과에 따라 정한다.
- 부수 비용: 소속과 본문 수명을 구분하면 UI/Helper의 ID 조회와 수거 조건을 함께 설계해야 한다. 반대로 단순 `isPinned`만으로 일반 삭제·해제·재사용을 처리하면 필요한 제품 의미를 빠뜨릴 수 있다. 대상은 이 점을 이미 Gate1과 M02/M09/M10/M11에 배정했다.

## 선택지 비교와 이상적 최종 상태

이 비교는 주인님에게 새 결정을 요구하는 절차가 아니다.

| 경로 | 이점 | 비용·한계 | 판단 |
| --- | --- | --- | --- |
| Core Data 관리형 후보를 먼저 probe | 로컬 변경·삭제 전송 추적을 플랫폼에 맡기고 전송 엔진을 하나로 유지 | 이관·history 소비·모델 제약, OFF/ON·프로세스 적합성 미확인 | **베스트 프랙티스: 현재 단계 권장.** 사용자 확정 방향이며 실제 API 한계를 작은 격리 시험으로 먼저 판별한다. |
| 파일+CKSyncEngine 재설계 | 현행 본문 저장을 재사용할 여지가 있고 전송 상태를 직접 통제 가능 | 자체 삭제/재개/복구 상태 구현과 검증 범위가 늘 수 있음; 총비용 우위 미확인 | Gate0 실패 근거가 생기면 비교할 대안. 현재 동시 구현 불필요. |
| 동기화용/비동기화용 별도 store 사이 이동·병합 | OFF의 연결 분리 경계를 만들 여지 | store 간 항목·삭제·계정 귀속 이동과 재개 프로토콜 추가; 현재 요구만으로 필요성 미입증 | 현 단계 비권장. 관리형 후보 검증 전 추가하지 않는다. |

이상적 최종 상태(IFR)는 로컬 수집·검색·붙여넣기가 네트워크와 독립적으로 기존 내용 형식을 사용하고, 단일 플랫폼 미러링 소유자가 같은 계정의 변경을 전달하며, 앱은 일반/고정 소속·만료·중복과 사용자 상태만 책임지는 것이다. 문서는 이 방향으로 가며, 성립 여부를 Gate0/Gate1에서 확인하도록 제한한다.

## 읽은 파일

1. `/Users/crobat/.codex/plugins/cache/egm/egm/0.1.1/agents/inventive_catalyst.md`
2. `/Users/crobat/.codex/plugins/cache/egm/egm/0.1.1/resources/document_standards/zoom-out-standard.md`
3. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/manifest.json`
4. `/Users/crobat/dev/tidytap/docs/CLIPBOARD_PINBOARD_ICLOUD_PLAN.md`
5. `/Users/crobat/dev/tidytap/docs/CLIPBOARD_PINBOARD_UI_WORK_PLAN.md`
6. `/Users/crobat/dev/tidytap/docs/CLIPBOARD_HISTORY_URS.md`
7. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/sources/coredata-sync.md`
8. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/sources/coredata-limits.md`
9. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/sources/model-limits.md`
10. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/sources/store-configuration.md`
11. `/Users/crobat/dev/tidytap/docs/reviews/clipboard-managed-sync-2026-11-13/sources/history-consumption.md`

과거 보고서·대화·메모리는 조회하지 않았다. UI local_context에 포함된 과거 검토에 대한 서술은 판정 근거로 쓰지 않았고 연결된 보고서도 열지 않았다. 외부 실시간 조회 없이 지정된 공식 문서 사본으로만 근거를 평가했다. 제품 시험·빌드·코드/계정/클라우드 변경은 수행하지 않았다. 이 원시 결과 파일 외에는 작성하지 않았다.

주인님, 검토는 완료했으며 실제 OFF/ON·두 Mac 동기화·최종 모델은 시험하지 않았다. 현재 제품 장애를 발견한 결과가 아니고, 관리형 후보의 적합성은 예정 관문 전까지 미확인이다.
