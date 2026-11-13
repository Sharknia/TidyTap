# Gate1 금붕어 검토

주인님, 독립 설계/구현준비 두 역할이 각 persona/표준·대상 전체·상위/UI/기존 코드 경계를 읽고 검토했다. 실행/수정은 하지 않았다.

| 지적 | 등급 | 보완 |
| --- | --- | --- |
| G-D01/G-I01 첫 귀속과 캡처 race | Major/높음·실손실 미확인 | 복사 반입을 폐기하고 전 프로세스 공통 routing lock·동일 store 귀속·단일원자 metadata로 대체 |
| G-D02/G-I02 cross-process 최신 값 | Major/높음·오동작 미확인 | fresh context/handle과 App remote-change→session 검사→snapshot 공통갱신. 앱 token merge 없음 |
| G-I03 원본 변경 reader | Major/높음 | 구 entries 미사용·잠금 아래 비파괴 Data decode·실패 원본불변 시험 |
| G-D03 원격 pin 초과 | Major/높음 | 논리 ID별 합계·수신 초과는 보존·로컬 신규만 거부 |
| G-D04 붙여넣기 계정 | Major/중간·경합 미확인 | route/generation IPC·Helper 조회/쓰기 직전 검증 |
| G-I04 파일 경계 | Nit/낮음 | 실제 시험/문서 경로 보완 |

실제 두 Mac/서명 자원 부재는 새 구현 차단으로 세지 않았다. 보완은 문서에 반영했으며 이 단계의 추가 독립 재검토는 하지 않았다. 다음 저장 구현의 코드/시험 금붕어가 적용 결과를 검토한다.
