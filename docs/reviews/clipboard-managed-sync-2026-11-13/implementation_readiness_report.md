# 9단계: 구현 준비도·코드 연결·문체 검토

대상: 개정 0.4 DetailedRange 60~165. 각 검토자는 새 대화 맥락에서 지정 persona·standard(해당하는 경우), 대상, manifest의 local_context 2개와 source_context 5개를 모두 읽었다고 보고했다. 이전 단계 보고서·대화·메모리는 공급하지 않았다.

## 구현 준비도 — managed09_readiness, 완료

| 범위 | 판정 |
| --- | --- |
| 조사·Gate0-A 문서 작성 | 착수 가능 |
| Gate0-B probe 코드 | Gate0-A의 실제 구성·파일·전환·시험 절차 확정 후 가능 |
| P1~P4 제품 구현 | Gate1의 최종 설계 전이므로 zero-decision 미충족 |
| 관리형 채택·배포 | 실제 두 Mac·최종 후보·schema 검증 전으로 미판정 |

### I01 — Blocker / 해당없음

전체 제품의 구현 준비 판정에 한한 Blocker다. 위치 87·95~99·115~121·153행. 최종 모델/API·계정·충돌·이관·파일 목록은 Gate1에 예정돼 있다. 새 누락이나 현재 제품 장애가 아니다. Gate1 완료 후 그 산출물을 포함한 구현 준비 검토가 필요하며 현재 문서를 제품 구현 승인으로 쓰지 않는다.

### I02 — Major / 중간

새 누락. 위치 113~114·132~135·145~147·151행. Gate0-A에 구체적인 시험 관찰·중단·판정 프로토콜 확정이 명시되지 않았다. 특히 M04 실제 ACK 영속화 전 경계를 인정할 증거, M07 OFF 완료와 이후 송수신 부재의 증거, 고정 관찰 기간의 값·시작/종료 조건이 실행자 선택으로 남아 있다. 실제 오판정이나 전송 발생은 미확인이다.

최소 개선: Gate0-A에 M01~08·12·15 각각 사전 상태·합성 ID·순서·관찰 신호·중단 지점·관찰 기간·성공/실패/부분/미실행 조건을 잠그는 산출물을 추가한다. 통제할 수 없는 SDK 경계는 증거와 미실행 조건을 적는다. 진단 증거의 경로와 가명화 범위도 확정한다. 앱이 내부 SDK 재시도를 직접 제어하라는 뜻은 아니다.

## 문체 — managed09_style, 완료

| ID | 원 EGM / 사용자 등급 | 위치 | 최소 개선 |
| --- | --- | --- | --- |
| U01 | Nit / 낮음 | 153행 | ‘공유/캐시 한도’를 ‘공통 라이브러리/기기별 캐시 한도’로 통일 |
| U02 | Nit / 낮음 | 77·153행 | ‘몰래 켜지 않음’, ‘조용히 줄이지 않고’를 로그인 항목 자동 활성화 금지와 범위 유지/실패 근거 기록 계약으로 기술 |
| U03 | Nit / 낮음 | 140행 | ‘미러링 위조 없음’을 수집 누락 방지·중단 상태를 최신/완료로 표시하지 않는다는 관찰 가능한 조건으로 기술 |

두 역할 모두 필수 persona·대상 전체·지정 맥락 전체의 읽기 완료를 보고했다. readiness는 implementation-readiness-standard도 읽었다. 파일 수정·빌드·시험·실제 CloudKit·계정/자원 변경은 하지 않았다.

## 코드 연결 — managed09_codebase, 완료

### R01 — Major / 중간

새 누락. 위치 95~99·115~116·153행. 현행 ClipboardHistoryStore.swift 46~50행은 디렉터리 0700, 183~200행은 임시 본문 0600과 원자적 교체를 사용한다. 새 SQLite/WAL/SHM/외부 binary·staging·백업의 사용자 전용 접근 유지 계약과 검사가 빠져 있다. 실제 권한 약화나 데이터 노출은 미확인이다.

최소 개선: Gate1에 계정/라이브러리/staging/백업 디렉터리의 사용자 전용 접근, 본문과 부속 파일의 타 사용자 노출 차단을 현행 0700/0600 수준으로 명시하고 생성·재실행·이관·백업 뒤 검증을 넣는다.

기존 저장소 생성 호출자·Helper ID 조회·독립 scalar 설정·실행 주체·서명/패키징은 계획 경계와 맞으며, 예정 선결 작업으로 해당없음이다.

읽기 보고: persona·implementation-readiness-standard·대상 전체·local_context 2개·source_context 5개. 연결 코드 ClipboardHistoryStore/ClipboardCaptureService/TidyTapProduct/TidyTapLaunchSmoke/AppDelegate/InputFeatureAdapters/FinderFeedbackAppHost/HelperRuntime/HelperLifecycle/App main 전체 및 설정·시험·프로젝트·공개 signing·smoke/clipboard gate/preview·release packaging/검증 스크립트 관련 부분. 과거 보고서·대화·메모리·실계정은 사용하지 않았으며 쓰기·빌드·시험은 하지 않았다.
