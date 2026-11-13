# P1 저장·이관 금붕어

독립 codebase/준비도 두 역할이 persona·준비도 표준·Gate1 설계(5절포함)·엔진/제품호출자·시험/로그를 읽고 완료했다. 실제실행은하지않았다.

| 지적 | 등급 | 반영 |
| --- | --- | --- |
| P1-R1 콘텐츠 기반ID 로그 | Major/높음·실제민감로그미확인 | promotion/selection ID 로그제거, 검색/본문/hash 로그도제거 |
| P1-I1/R3 이관재시도 | Major/중간 | 정상+불량혼합 원본보존·부분반입없음·교정재시도·DB save뒤marker실패 재시도시험 |
| P1-I2/R3 귀속실패 | Major/중간 | mode설정/fsync완료한 임시파일을rename, 성공publish뒤fallible chmod제거. readonly routing parent실패시원문/route보존시험 |
| P1-I3/R3 보호경계 | Major/중간 | 기존 store tree를 load전 symlink/권한검사. routing/marker권한보정. 외부target불변·0600/0700시험 |
| P1-I4/R3 codec | Major/중간 | image/HTML/RTF 재열기·NFC/NFD ID와원문byte보존시험 |
| P1-R2 계정붙여넣기 | Major/중간·경합미확인 | P3의 account switch연결전 필수 IPC·UI표시세션검사로유지. 아직계정전환제품호출자없음 |

초기엔진148개(1개skip)실패0, 새저장12개실패0, 앱build exit0. Helper시험의새저장소읽기와fixture경로분리를맞춘뒤앱suite exit0. 보완뒤새저장17개통과. 전체suite는P2일괄연결뒤다시수행한다.

독립 재검토: v2_p1_reaudit는 persona·표준·설계·지정 구현·17개 시험 로그를 읽고 새 차단/높음 없음으로 보고했다. 중간(Major): 필수 필드가 없는 행을 조용히 제외하는 점을 지적했다. 부모는 누락도 invalidStore로 처리해 빈 데이터로 성공 표시하지 않도록 수정했다. 계정/IPC/원격 갱신은 P3 선행 연결로 확인했다. 마지막 오류 방어는 후속 통합 시험/검토에서 다시 대조한다.
