# 재검토 9단계: 구현 준비도 최초 판정

- 대상: 55~221행, CloudKit 시험 격리 보완 전 사본 `target_snapshot_after_t01.md`
- 검토자: r2_09_readiness, r2_09_codebase, r2_09_style. 모두 완료.
- 결과: 신규 Major 1건·Nit 1건. 아래 보완 후 이 단계만 새 문맥으로 재검토 1회 진행한다.

## K01 / Major / 중간: CloudKit 시험 격리 경계 누락

- 검토자: r2_09_codebase
- 대상: 131·166·187·193·197·200행
- 근거: `Sources/Shared/TidyTapLaunchSmoke.swift:5~28`은 환경 변수와 UserDefaults suite만 분리한다. `Sources/Shared/TidyTapIPC.swift:22~25`는 로컬 알림 object만 분리한다. `Scripts/launch-smoke.sh:13~16`과 Xcode TestAction도 로컬 suite·저장 경로만 바꾼다. 실제 CloudKit 클라이언트·컨테이너·환경·계정·DB·zone을 분리하는 기존 장치는 없다.
- 영향: 로컬 suite만으로 클라우드도 격리됐다고 간주하면 향후 sync-on 시험이 실제 사용자 개인 DB와 섞이거나 ad-hoc 시험이 권한 오류로 실패할 수 있다. 현재 실제 접근·유출은 미확인이다.
- 권고: 일반 XCTest/smoke 실제 연결 금지·가짜 전송 주입, 실제 시험의 명시적 연결 영역/계정·합성 데이터·설정 검사, Gate0/1 계약과 LaunchSmoke 파일 경계 추가.
- 처리: PROPOSE FIX. 계획에 CloudKit 시험 연결 격리 절을 추가했다. 시험 표식 오류·전송 주입 누락은 실제 연결로 대체하지 않는다. 실제 시험의 후보/서명/container/환경/private DB/계정 별칭/zone 범위를 확인하며 운영 데이터로 대체하지 않는다. AC-S15/E11 및 관련 코드·scheme/스크립트/시험 경로를 추가했다. 실제 연결은 이번 작업에서 하지 않았다.

## U01 / Nit / 낮음: 의미를 더하지 않는 완료 경고

- 검토자: r2_09_style
- 대상: 136행
- 내용: ‘생성 예정 파일 부재를 구현 완료로 보지 않는다’는 문장은 앞서 정의한 생성 예정 상태·실제 코드 착수 조건에 별도 결정을 더하지 않는다.
- 권고: DROP, 이 문장만 삭제.
- 처리: PROPOSE FIX, 해당 문장 삭제. 파일 목록 선확정과 설계 산출물 조건은 유지했다.

## 이미 계획된 준비도 한계 / 해당없음

| 검토자 구분 | 원시 EGM 등급 | 해당 범위 | 판정 |
| --- | --- | --- | --- |
| Readiness 실행 주체·프로브 파일 | Blocker | 81~85·93·134~136행 | 정확한 실행 주체·권한·파일 목록을 Gate0 첫 산출물에서 정해야 하므로 프로브 코드 착수는 아직 불가. 조사·결정 문서는 가능 |
| Readiness 저장·API·정책·이관 | Blocker | 60~75·94·100·122·136행 | 기존 선결 설계가 남아 전체 Zero-Decision 표준 미통과. Gate1 산출물 전 제품 코드 작성 불가 |
| Readiness 시험의 남은 기대값 | Blocker | 179~180·185행 | E06·E07·동시 사건 결과를 설계 산출물에 기입한 후 시험 구현. 새 누락 아님 |
| Codebase K02 | Major | 61~68·83·94·100·134~136·179~185행 | 같은 선결 설계에 관한 중복 한계. 새 지적으로 집계하지 않음 |

Readiness는 파일 경계·여러 사건 기대값·단계별 자동/실기기 검증·명령이 구체화됐다고 확인했다. Codebase는 현재 경로와 Store·IPC 한계·Helper·로그 설명이 코드와 일치하며 생성 예정 파일의 부재를 오류로 계산하지 않았다. Style은 실행 주체·이관·수용 제한이 실제 결정에 연결돼 유지 대상으로 봤다.

## 완료 증거

세 검토자 모두 각 persona와 지정된 기준(Style은 별도 기준 없음), 대상·URS·피드백 검증·Apple 자료 4개 전문을 읽었다고 보고했다. Readiness는 Store·AppDelegate·HelperRuntime·HelperLauncher·Xcode를 대조했다. Codebase는 Store/Capture/Reader/Writer·패널·설정/IPC/Product·Helper·Xcode target/scheme·서명·패키징·smoke/gate·시험 인프라를 대조했다. Style은 표현 범위를 검토했다.

다른 리뷰·대화·메모리는 읽지 않았고 파일 수정·컴파일·시험·실제 계정/CloudKit 조회는 하지 않았다. 문서 수정은 완료 응답 후 주 에이전트가 적용했다.
