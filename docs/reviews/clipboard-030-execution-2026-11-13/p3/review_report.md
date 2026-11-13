# P3 금붕어 검토·보완

독립codebase/readiness 두역할이persona/표준·Gate1설계·전송/Coordinator/앱/Helper/설정/시험을읽고완료했다. 실제CloudKit실행은하지않았다.

| 지적 | 원등급/사용자등급 | 반영 |
| --- | --- | --- |
| S-R1/S-I1 active이벤트·OFF실패 | Major/높음 | SDK callback에서lock보호ID추적. store분리뒤관측active끝과weak이전owner해제확인. timeout/오류는pausing+retry, 저장OFF의도유지 |
| S-R2/S-I2 피드백호스트자동종료 | Major/높음·실전송영향미확인 | needsOwnerLifetime(ON의도/미러존재/종료재시도)에서자동종료차단. 초기OFF는기존종료유지. 늦은timer도재검사 |
| S-R3 entitlement빌드연결 | Major/중간 | MainRelease대상에선택적entitlement/profile설정연결, Helper에는권한없음 |
| S-I3 지연/실패시험 | Major/중간 | start throw·지연stop중pausing·마지막ON승리·stale변경무시·종료재시도/호스트수명시험추가 |

런타임profile구조파싱은추가하지않았다. 서명entitlement와Info container일치·embedded profile존재를검사하고실제profile유효성은OS서명/실환경수용으로구분한다. XCTest/smoke는실account provider와transport자체도거부한다. 실제CloudKit계정·프로파일·두Mac·SDK종료수용은미실행이다.

독립 재검토는 새 차단/높음 없음, 중간1건(저장 실패 복원 시 pauseNeedsRetry 누락)·낮음1건(OFF retry 설명)을 보고했다. 부모는 flag 필수 인자를 받는 UI 복원 메서드에 연결하고 OFF 실패/재시도 중 저장 실패 회귀 검사를 추가했다. 설명도 ON 복구/OFF 종료확인으로 맞췄다. 최종 종합 검토에서 현 소스를 다시 읽는다.
