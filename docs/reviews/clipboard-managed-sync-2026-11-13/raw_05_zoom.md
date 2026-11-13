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
