# UI 작업 계획 9단계 구현 준비도

- 검토 시점: target_snapshot_after_critic.md, 상세 84~178행
- 검토자: ui09_readiness·ui09_codebase·ui09_style, 모두 완료
- 결과: 새 Major 3건(사용자 중간)을 보완했다. Style 신규 지적 0건. 수정본은 이 단계 재검토 1회로 확인한다.

## R01 / Major / 중간: 같은 세션의 새 선택과 늦은 완료

- Readiness, 100~102·120·130·153행. 삭제 요청 중 탐색을 허용하면서 요청 당시 행 번호도 보존해 어느 탭의 어느 선택을 복원할지 불분명했다.
- 현재 코드는 `refreshAfterDeleting`가 전달 행을 현재 필터 결과에 적용한다. AppDelegate도 당시 행을 전달한다. 비동기 완료로 바꾸면 보관함 P2를 새로 선택한 뒤 과거 최근 기록의 행으로 돌아갈 수 있다. 현재 미구현이며 실제 재현은 미확인이다.
- 보완: 완료 직전 현재 탭·쿼리·필터·선택 ID·행·스크롤을 우선하는 공통 갱신으로 통합. `refreshAfterDeleting`를 제거하고 호출자/시험도 옮긴다. 현재 선택이 결과에 남으면 유지하고 사라진 경우에만 그 현재 행 기준 인접 선택. H1 삭제 뒤 P2/H3 선택과 H1 유지 세 경우의 UI-T09 기대값을 명시했다.

## K01 / Major / 중간: U1의 추가 시험 호출자

- Codebase, 92·129·133행. `TidyTapSettingsTests.swift:39~40`이 실제 패널 updateEntries를 호출하며 같은 시험 타깃에 포함되지만 U1 정확 목록에는 없었다. 동기화 설정의 U1~U3 목록만으로 변경 시점이 고정되지 않았다.
- 보완: U1 목록에 정확한 파일을 추가하고 1,000개 기록 시험을 명시적 history-only snapshot으로 바꾸도록 지정했다. 메서드/호출자 변경은 같은 단계에 수행한다.

## K02 / Major / 중간: 패널 fixture 언어 적용

- Codebase, 131·135·156행. 현재 renderer는 SettingsViewController에 언어 번들을 주입하지만 패널은 기본 String(localized:)와 인자 없는 초기화를 사용한다. 기존 fixture 언어만 복사하면 한/영 패널 문구를 재현할 수 없다.
- 보완: 기본 `.main`인 localizationBundle 초기화 인자, 기존 house pattern의 번들 조회 함수와 모든 패널 문구/접근성 이름 적용을 명시했다. renderer의 기존 localizedBundle(language:)를 패널에 직접 전달하며 ko/en 기대 문자열을 시험한다.

## 기존 한계 / 해당없음

Gate0/1의 저장·계정·고정 전용 ID 조회·접수 순서·동기화 실행/취소/상태 계약은 이미 선행 조건으로 계획돼 있다. 새 누락으로 집계하지 않는다. 전체 Zero-Decision 실행은 아직 미통과이며 U0 조사·합성 fixture 설계는 가능하다.

Style 검토자는 문구·미정·기준안·실기기 미실행의 범위를 구체적인 독자 판단과 연결된 KEEP으로 보았고 신규 Blocker/Major/Nit 0건을 보고했다.

## 완료 증거

세 검토자가 persona·지정 기준(Style 별도 기준 없음), 대상·상위 계획·URS·피드백 검증·Apple 자료 4개를 전문 읽었다고 보고했다. Readiness는 패널의 검색/선택/키/숨김과 AppDelegate 삭제/갱신·Coordinator·renderer·전체 호출자를, Codebase는 실제 모든 패널 호출자·설정/엔진/Helper·Xcode 타깃/scheme·시험 helper/renderer·스크립트를 대조했다. 다른 리뷰·대화·메모리는 읽지 않았다.

파일 수정·빌드·시험은 하지 않았다. 문서 보완은 완료 응답 후 주 에이전트가 적용했다. 실제 키·IME·붙여넣기·CloudKit·두 Mac 수렴은 미검증이다.
