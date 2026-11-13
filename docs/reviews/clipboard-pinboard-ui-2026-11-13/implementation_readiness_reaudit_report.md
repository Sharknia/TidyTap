# UI 작업 계획 9단계 재검토 1회

- 검토 대상: target_snapshot_after_readiness.md, 상세 84~182행
- 검토자: ui09_readiness_reaudit·ui09_codebase_reaudit·ui09_style_reaudit, 모두 완료
- 결과: 새 Major 1건(중간), Nit 2건(낮음). 문서에 추가 보완했으나 그 최종 보완 뒤 독립 재검토는 하지 않았다. 이 단계의 재검토 상한 1회를 사용했다.

## 재검토 R01 / Major / 중간: 저장 성공 뒤 Helper 실패의 구분

- Readiness, 108~110·137행. 현재 SettingsCoordinator.save는 preferences를 먼저 쓴 뒤 ensureHelperRunning에서 같은 throws로 실패한다. 따라서 기존 save의 성공/실패를 sync 의도의 저장 성공/실패와 동일시할 수 없다.
- 영향: 값이 저장됐는데 동기화 실행 주체에 전달하지 않거나, Helper 오류를 저장 실패로 잘못 표시할 수 있다. 실제 새 기능의 실패 재현은 미확인이다.
- 최종 문서 보완: sync 의도는 입력 Codable snapshot과 분리된 동일 preferences 도메인의 전용 Bool 키로 저장한다. 기존 store/protocol에 scalar read/write API, Coordinator의 저장 전용 메서드, 전용 UI delegate를 둔다. 이 경로는 입력 request/apply ID·로그인 항목·입력 Helper 기동을 변경하지 않는다. 성공 후 sync 실행 주체 적용을 별도로 요청한다. 입력 설정 save가 뒤에 실패해도 독립 sync 값/스위치를 되돌리지 않게 하고 UI-T17을 추가했다.
- 확인 상태: 원시 지적은 읽기 리뷰로 확인됐고 문서 보완은 주 에이전트가 코드 대조 후 적용했다. 이 새 저장 경계는 추가 독립 검토가 필요하다. 제품 코드 변경·동작 시험은 하지 않았다.

## 재검토 U01 / Nit / 낮음·미확인: ‘동기 전달’ 표현

- Style, 98행. 즉시 콜백 호출과 MainActor 동기 I/O 요구가 혼동될 수 있다.
- 반영: 최신 조회 결과 처리에서 MainActor 콜백을 즉시 호출하며 결과 준비 뒤 추가 Task/await/지연 큐를 넣지 않는 UI 전달 순서라고 풀어 썼다. 디스크 I/O를 MainActor에서 동기 실행하라는 요구와 구분했다. 별도 독립 재검토는 하지 않았다.

## 재검토 U02 / Nit / 낮음: 명령 실행 부정의 중복

- Style, 141행. 현재 작업의 시험 미실행은 뒤에서 명시하므로 명령 옆의 같은 부정 문장은 별도 판단을 더하지 않는다.
- 반영: 그 문장만 삭제했다. 단계별 필수 검증과 실제 CloudKit 연결 차단은 유지했다. 별도 독립 재검토는 하지 않았다.

## Codebase 판정과 기존 선결 조건

Codebase는 새 누락·불일치 0건으로 보고했다. 실제 패널 호출자·배열 갱신/삭제 경로·키 창/조합 처리·세그먼트 조회·설정 모델/저장·renderer/언어 번들·시험 mock을 대조했다. R01 이후 마지막 저장 경계 변경에 대한 통과 판정은 아니다.

Gate0/1 저장 API·고정 전용 ID·계정별 직렬 처리·실행 주체/적용 계약은 이미 명시된 선행 조건(해당없음)이다. 전체 Zero-Decision 준비도는 미통과이고 U0 조사·합성 fixture 설계는 가능하다.

## 완료 증거

세 검토자가 persona·지정 기준(Style 별도 기준 없음), UI 전체 182행·상위 계획·URS·피드백·Apple 근거 4개를 전문 읽었다고 보고했다. Readiness는 SettingsCoordinator 89~180행·AppDelegate 778~789행과 패널·시험을, Codebase는 Store·패널·AppDelegate·Coordinator·renderer·설정 mock·타깃/scheme 등을 확인했다. Style은 문서 표현을 확인했다.

다른 리뷰·대화·메모리 조회, 파일 변경·생성·빌드·실기기/CloudKit 시험은 하지 않았다. 문서 보완은 완료 응답 뒤 주 에이전트가 수행했다.
