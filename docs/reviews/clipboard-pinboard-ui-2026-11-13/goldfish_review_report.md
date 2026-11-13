# UI 계획 지적사항 처리 기록

- 상태: 문서 보완 적용. 마지막 중간 등급 저장 경계 보완은 독립 재확인 전이다.
- 대상: `docs/CLIPBOARD_PINBOARD_UI_WORK_PLAN.md`
- 원칙: 원시 EGM 등급과 사용자 등급을 보존하고, 문서 보완과 제품 구현/시험 완료를 구분한다.

| 출처 | EGM / 사용자 등급 | 분류·반영 | 확인 상태 |
| --- | --- | --- | --- |
| 이해도 추가 요구 재검토 C01 | Major / 중간 | PROPOSE FIX. 단일 UI 변경 제한은 표시 세션별, 새 창 요청 허용·계정별 저장 접수 순서·표시 시 계정 핸들 고정 명시 | 이후 전체 재검토에서 반영 확인 |
| 이해도 추가 요구 재검토 C02 | Major / 중간 | PROPOSE FIX. 첫 snapshot 거부는 show false·패널 미표시·기존 열기 오류 경로, 표시 중 거부만 유효 목록 유지 | 이후 전체 재검토에서 반영 확인 |
| 비평 T01 | Nit / 낮음 | PROPOSE FIX. 진입 비용을 보관함 전환 1회의 실제 조작으로 풀어 씀 | 전체 재검토에서 반영 확인 |
| 비평 T02 | Nit / 낮음 | PROPOSE FIX. 모호한 시간을 실제 동기화 지연과 미수신 변경의 문제로 구체화 | 전체 재검토에서 반영 확인 |
| 준비도 R01 | Major / 중간 | PROPOSE FIX. 삭제 전 행 전달을 제거하고 현재 탭·선택 우선 공통 갱신, 기존 refreshAfterDeleting 삭제와 사건별 기대값 명시 | 재검토에서 같은 누락 재지적 없음 |
| 코드 K01 | Major / 중간 | PROPOSE FIX. U1에 TidyTapSettingsTests 정확 경로와 1,000개 history-only snapshot fixture 전환 추가 | 재검토에서 같은 누락 재지적 없음 |
| 코드 K02 | Major / 중간 | PROPOSE FIX. 기본 main 언어 번들 주입·house 조회 패턴·renderer 언어 직접 전달·기대 문자열 검사 | 재검토에서 같은 누락 재지적 없음 |
| 준비도 재검토 R01 | Major / 중간 | PROPOSE FIX. sync 전용 preferences 키/read-write·저장 메서드·delegate로 입력 Helper save와 분리, UI-T17 추가 | 최종 보완 뒤 추가 독립 검토 없음 |
| 표현 재검토 U01 | Nit / 낮음·미확인 | PROPOSE FIX. 동기 전달의 의미를 UI 콜백 순서로 구체화하고 I/O 스레드 강제와 구분 | 최종 보완 뒤 추가 독립 검토 없음 |
| 표현 재검토 U02 | Nit / 낮음 | PROPOSE FIX. 중복된 시험 미실행 부정 문장만 삭제 | 최종 보완 뒤 추가 독립 검토 없음 |

새 기능의 실제 데이터 손상·전역 충돌·저장 실패를 재현했다고 주장하지 않는다. 문서 내용의 추가 독립 검토는 남겨 둔 상태이며, 검토 없이 마지막 Major가 통과됐다고 기록하지 않는다.
