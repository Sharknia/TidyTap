# P2 금붕어 검토·보완

독립 codebase/design 두 역할이 persona/표준·UI계약·Gate1·패널/앱연결·시험/문구를읽고완료했다.

| 지적 | 원등급/사용자등급 | 반영 |
| --- | --- | --- |
| UI-R01 기존렌더높이실패 | Blocker/차단 | 탭44pt추가기대값·밀집높이498맞추고앱suite재통과 |
| UI-D01 검색중선택상실 | Major/중간 | inFlightSelection·scroll문맥을연속갱신/탭저장에전달, burst+왕복회귀시험 |
| UI-R02/D02 경계시험 | Major/중간 | marked/resign거부·숨김이벤트반환·고정실패/마지막해제·새세션요청중old실패시험 |
| UI-R03/D03 패널렌더/언어 | Major/중간 | 기존Renderer에한/영×480/800×두탭/이미지/빈/두오류20장, AppKit offscreen모드명시 |
| UI-R04 검색취소 | Nit/낮음 | paste도검색세대증가·task취소/상태정리 |
| UI-D04 남은scroll | Nit/낮음 | finish조기반환defer정리·show/close/paste초기화 |

엔진154(1skip)실패0, 앱189실패0. build/clipboard-030-app-tests-p2-reviewed.log와 build/clipboard-030-engine-p2.log, build/clipboard-030-ui/장면을확인했다. 실제IME·다른앱삽입·보조기술·iCloud는미실행이다. P3설정/계정/remote연결은후속필수이며P2새결함으로세지않았다.

독립재검토는새차단/높음없음,중간2건(오른쪽pin표식잘림·언어assert부족)을보고했다. 부모는표식을왼쪽icon badge영역으로옮기고control/빈상태/접근성번역과가시영역assert를추가했다. 보완후P3연결포함앱206개실패0. 마지막UI보완은P4종합검토에서대조한다.
