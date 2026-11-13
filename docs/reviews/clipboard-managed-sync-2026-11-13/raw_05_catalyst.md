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
