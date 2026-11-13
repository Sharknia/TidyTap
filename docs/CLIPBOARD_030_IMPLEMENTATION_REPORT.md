# TidyTap 0.3.0 구현 결과

주인님, **보관함·최근 기록 탭·독립 동기화 옵션·Core Data/CloudKit 전송 코드를 제품에 구현했다.** 실제 두 Mac 검증이 불가능하다는 이유로 구현을 멈추지 않도록 범위를 바로잡았다. 최종 종합 검토와 보완 확인을 마쳤으며 공개 릴리즈나 설치본 교체는 수행하지 않았다.

## 구현한 동작

| 범위 | 결과 |
| --- | --- |
| 저장·이관 | Core Data 일반 기록/고정의 수명 분리, 같은 본문의 안정적인 논리 ID, 고정 전용 항목 사용, 삭제/전체 삭제의 고정 보존. 구 파일 비파괴·멱등 이관과 실패/권한 방어 |
| 보관함 UI | 최근 기록으로 열기, 최근/보관함 탭, 패널 내부 ⌘1/⌘2. 탭별 검색/선택/스크롤, 고정·해제·일반 삭제, 늦은 검색/변경 응답과 세션 검사 |
| 동기화 옵션 | 입력 설정과 독립된 기기별 Bool. 기본OFF. 저장 실패와 적용 실패 구분. 종료 미확인은 ‘끄는 중’과 재시도로 유지 |
| 관리형 전송 | 실제 NSPersistentCloudKitContainer/private DB 연결 코드. 같은 SQLite/history로 재개, active 이벤트·이전 owner 해제 확인. XCTest/smoke의 실제 계정/transport 호출 차단 |
| 계정·붙여넣기 | 최초 계정은 기존 local store를 원자적으로 귀속. A→B는 별도 store. 표시 handle과 route/generation을 붙여넣기까지 전달하고 Helper의 조회부터 write/key-post까지 같은 routing lock 유지 |
| 버전·릴리즈 준비 | 앱/Helper0.3.0(16), 선택적 entitlement/profile 연결, 서명·CloudKit 메타데이터 검사기, 운영 스키마/서명 구성 안내. 공개 릴리즈는 구성 없는 후보를 거부 |

고정 본문은 일반 기록과 독립적인 사본을 보유한다. 서로 다른 순서로 오는 일반 만료/삭제와 고정 변경이 고정 내용을 잃게 하지 않기 위한 선택이며 UI에는 본문 하나를 제공한다. 고정 수신 초과는 보존하고 신규 로컬 고정만 제한한다.

## 확인한 범위

| 검사 | 결과·한계 |
| --- | --- |
| 엔진 전체 |156개, 실패0·live HID1개 건너뜀 |
| 앱 XCTest |209개, 실패0. 실제 CloudKit은 fake/차단 경계로 시험 |
| 기동 smoke | 설정 창·중복 프로세스·Helper 종료/재시작·업데이트 정리 확인. 수정 후 live 상태 해시 불변 |
| 클립보드 startup gate | 격리 Helper 단축키 탭 시작 확인. 실제 대상 앱 삽입 전체의 통과는 아님 |
| UI 렌더 | 한/영·480/800pt·두 탭/이미지/빈 상태/두 오류20장. AppKit offscreen이며 설치 기기 수용과 구분 |
| 패키징 회귀 | release 순서, preview source/격리·Finder metadata·installer layout 검사 통과 |
| CloudKit 구성 검사기 | 표준 unittest3개·불일치8변형·미설정 preview 허용/release 거부 확인. 실제 signed profile positive는 미실행 |
| 로컬 프리뷰 | ad-hoc0.3.0 프리뷰 DMG를 제품 수정 반영 후 재생성. 설치·공개 배포 아님 |

[시험 요약](reviews/clipboard-030-execution-2026-11-13/p4/check-results.json)과 [앱 결과](reviews/clipboard-030-execution-2026-11-13/p4/app-test-summary.json), [실행 현황](CLIPBOARD_030_EXECUTION.md)에 단계별 기록을 연결했다.

## 검토와 보완

[Gate1](reviews/clipboard-030-execution-2026-11-13/gate1/review_report.md), [P1](reviews/clipboard-030-execution-2026-11-13/p1/review_report.md), [P2](reviews/clipboard-030-execution-2026-11-13/p2/review_report.md), [P3](reviews/clipboard-030-execution-2026-11-13/p3/review_report.md)에서 새 대화 맥락의 금붕어를 사용했다. 초기 계정 귀속/캡처 race, 이관 실패·권한, 콘텐츠 기반 ID 로그, 연속 검색 선택, OFF 종료 확인/재시도, 피드백 호스트 수명 등을 보완했다.

[P4 종합 검토](reviews/clipboard-030-execution-2026-11-13/p4/review_report.md)는 코드 감사 새 지적0건, 회귀시험/문서 중간3건 보완 후 재검토 새 지적0건으로 마쳤다.

P4 기동 검사에서 기존 입력/권한 IPC가 시험 suite 밖의 설치 Helper에도 전달될 수 있는 경로를 발견했다. 첫 검사에서 HID/단축키 매핑은 같았으나 production preferences hash가 달라졌다. 원본 값을 추정해 되돌리지는 않았다. 입력·권한·Finder-ready 메시지까지 suite object로 분리한 뒤 기동 검사를 다시 수행했고 세 상태 해시가 모두 유지됐다. 이 초기 검사에서 어떤 개별 preference 값이 달라졌는지는 해시만 보관해 확인하지 못했다.

## 남은 실환경 관문

- 실제 CloudKit App ID/container/profile 연결·Development schema 초기화/Production 승격과 두 Mac 송수신, 삭제 충돌·OFF 내부 종료·기기 시계/용량·지원 OS 수용은 미실행이다. [구성 안내](CLIPBOARD_ICLOUD_RELEASE_SETUP.md)를 따른다.
- 실제 계정 전환과 foreground 앱 삽입·IME·보조 기술 수용도 자동 시험으로 승격하지 않았다.
- 기본 unsigned/ad-hoc 빌드는 CloudKit 구성 검사를 통과하지 않으므로 ON 의도를 저장해도 구성 안내를 표시하며 실제 계정 조회/전송을 시작하지 않는다. 이 프리뷰를 동기화 사용 준비가 끝난 공개 릴리즈로 취급하지 않는다.
- 실제 사용자 기록을 새 저장소로 이관하거나 설치된 앱을 교체하지 않았고, Appcast/태그/공개 배포도 변경하지 않았다.

[0.3.0 로컬 프리뷰 DMG](../build/artifacts/TidyTap-0.3.0-preview-adhoc/TidyTap-0.3.0-preview-adhoc.dmg) · [SHA256](../build/artifacts/TidyTap-0.3.0-preview-adhoc/TidyTap-0.3.0-preview-adhoc.dmg.sha256). 동기화용 서명 구성이 없는 ad-hoc 프리뷰다.
