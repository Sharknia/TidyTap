# Finder 잘라내기 구현 검증

상태: 구현·자동 테스트·독립 리뷰 반영 및 핵심 Finder 실검증 완료 / 확장 시나리오 미검증

기준 브랜치: `feature/finder-cut-paste`, 시작점 `origin/dev`의 `3e88db4`.
환경: macOS 26.5.2 (25F84), Xcode 26.6 (17F113).

## 역할과 범위

- Sol: 입력 엔진과 임시 실행 검사 도구.
- Terra: 설정 저장, Helper 적용·실효 상태와 롤백.
- Luna: 기존 설정 화면과 현지화.
- 오케스트레이터: 통합·실제 동작 검증·단계별 커밋과 푸시.
- 각 구현은 대화 맥락을 넘기지 않은 새 Sol이 별도로 리뷰한다.

파일 소유를 분리한 공유 브랜치에서 작업한다. 제품 설치본과 운영 설정을 바꾸지 않는
검증 경로를 우선 사용한다. 릴리스·배포는 이번 구현 작업에 포함하지 않는다.

## 근거 기록

설계 및 원본 초점 검사는 [계획서](FINDER_CUT_PASTE_PLAN.md)와
[초점 실험](../Spikes/FinderFocusProbe/README.md)을 참조한다.

아래 결과는 검증 실행 후 기록한다. 계획과 테스트 코드의 존재만으로 통과 처리하지 않는다.

| 항목 | 상태 |
|---|---|
| 입력 엔진 단위 테스트 | 92개 통과 |
| 설정·Helper·화면 테스트 | 전체 100개 통과, 최종 문구 변경 후 UI 15개 추가 통과 |
| 실제 Finder 이동·복사 | 전역 키로 네 보기 이동 및 일반 복사 확인 |
| 이름 변경·검색 등 텍스트 보존 | 이름 변경의 X/V 편집 및 원본 보존 확인. 검색 등 추가 입력창은 초점 분류만 검증 |
| 일반 C 즉시 초기화·연속 X·빠른 V | X 뒤 50ms 후 C → V에서 복사 확인. 연속 X·빠른 V는 자동 테스트 |
| 독립 구현 리뷰 | 화면·Helper 결함 없음, 엔진 수정 및 잔여 제약은 아래 참조 |
| 브랜치 커밋·푸시 | 설계 9392495, 엔진 a218e74, 설정·Helper 22b223a 푸시 완료 |

## 지원 제약

- 파일 목록과 파일 내용은 저장하지 않는다. 이동 명령은 한 번 전달하면 기억을 지운다.
- Finder 작업 실패·취소 후 재이동은 원본에서 다시 잘라내야 한다.
- 외부 프로그램의 동시 클립보드 덮어쓰기와 시간 초과 이후 늦은 Finder 갱신의
  출처를 완전히 구별하는 것은 보장하지 않는다.
- 바탕화면과 다른 파일 관리자는 첫 지원 범위에 포함하지 않는다.


## 독립 리뷰와 반영

- 화면: 새 Sol 리뷰 후 권한 실패 안내에 남아 있던 마우스 전용 문구를 수정하고 회귀 테스트 추가.
- Helper 연결: 새 Sol 리뷰, 보고할 결함 없음. 자동 테스트 결과 재확인.
- 엔진 첫 리뷰: tap 비활성화 시 기억 초기화 누락과 지연 전송 실패 시 기억 소비를 수정.
- 엔진 후속 리뷰: 일반 키의 불필요한 Pasteboard IPC 제거, AX 전체 조회 예산 도입.
- 엔진 최종 리뷰의 P2: 복사 확인 중 다른 Finder 파일 목록으로 이동해 V를 누르면
  해당 입력을 폐기한다. 문맥이 바뀐 미확인 복사를 이동시키지 않는 보수적 계약으로 유지한다.
  이 경우 원본에서 다시 X가 필요하며 정상적인 모든 창 전환이 무손실이라는 보장은 하지 않는다.

## 오케스트레이터 검증

- `swift test --package-path Packages/TidyTapInputEngine --scratch-path /tmp/tidytap-finder-final-package`: 92 tests, 0 failures.
- `xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug -derivedDataPath /tmp/tidytap-finder-root-build CODE_SIGNING_ALLOWED=NO test`: 100 passed, 0 failed/skipped (xcresult summary 확인).
- 한국어 화면 렌더링에서 신규 토글·설명과 기존 하단 설정이 겹치지 않음을 확인.
- 임시 Swift 전역 CGEvent 실험: 목록 보기의 source=false/target=true로 이동 확인,
  일반 C는 source=true/target=true로 복사 확인. 임시 파일만 사용.
- 다른 앱이 전면이었던 실행은 통과로 집계하지 않는다. 이후 검사 코드에 전면 Finder와
  테스트 창 제목 확인을 추가했으며 loginwindow 상태에서는 키를 전송하지 않고 중단했다.
- 자동 UI 도구의 키 전송은 전역 tap 경로의 증빙으로 사용하지 않는다.
- 갤러리 실험 1회는 원본이 유지되고 목적지에 복사되는 결과를 관찰했다. 사전 초점 확인도 실패했으므로 원인을 확정하지 않았으며 성공으로 집계하지 않는다.
- 당시에는 아이콘·계층·갤러리의 실제 이동과 텍스트 편집 실검증을 중단했다.
  잠금 해제 후 재실행 결과는 아래에 별도로 기록한다.


최종 UI 문구 수정 후 `SettingsViewControllerTests` 15개 통과. 한·영 정상 화면 모두
1120×1520 픽셀(560×760pt)로 확인했다. 긴 영어 권한 설명으로 늘어나던 폭은 설명을
짧게 조정해 해결했다. 레이아웃 구조나 창 크기를 늘리지 않았다.

확장 실검증 및 실제 배포 대상 OS 확인 없이 출시 준비 완료로 판단하지 않는다. 설치본 교체,
로그인 항목 변경, 릴리스 또는 병합은 수행하지 않았다. 임시 키 검사 프로세스는 종료했다.


## 잠금 해제 후 전역 키 실검증

사용자 승인하에 임시 Swift 코드로 CGEvent를 전역 입력 경로에 전송했다.
엔진은 제품 설정과 무관한 검사 프로세스에서 실행했다. 각 명령 전에 전면 Finder와
임시 검사 창을 확인하고, 조건이 다르면 키를 전송하지 않았다. 이름 변경 중에는
AXFocusedWindow가 없으므로 확인된 rename 텍스트 초점으로 검사했다.

| 시나리오 | 파일 시스템 / 텍스트 결과 |
|---|---|
| 목록 X → 대상 폴더 V | source=false, target=true |
| 아이콘 X → 대상 폴더 V | source=false, target=true |
| 계층 X → 대상 폴더 V | source=false, target=true |
| 갤러리 X → 대상 폴더 V | source=false, target=true |
| 일반 C → 대상 폴더 V | source=true, target=true |
| X → 50ms 후 일반 C → 대상 폴더 V | source=true, target=true |
| 이름 변경 X → V → Escape | 이름이 확장자만 남도록 잘렸다가 원래 이름 복원, 원본 파일 유지 |

사용자가 입력을 멈춘 동안 수행한 재실행에서 갤러리 이동도 통과했다.
이전 중단·실패 실행을 통과로 소급 처리하지 않는다. 기본 폴더 열기 연동으로 다른 앱이
선택되는 영향을 피하기 위해 검사 코드는 Finder의 selectFile 경로로만 탐색했다.
테스트 종료 후 검사 프로세스는 종료했다.

남은 확장 검사: 실제 외장 볼륨·읽기 전용 볼륨·연결 해제, 다중 파일 부분 실패,
Finder 충돌 대화상자 취소, 실제 권한 회수·복원 및 Secure Input, 다른 macOS 버전.
이 항목의 미검증을 핵심 이동·복사 테스트 통과와 구분한다.


## macOS Sequoia 15.1 최소 지원

- Debug/Release 앱·Helper 배포 타깃: 15.1. Info.plist는 배포 타깃 값을 사용한다.
- AppKit Glass 카드는 26 이상에서만 생성하고, 그 이전은 기존 semantic surface로 표시한다.
- 패키지 자체의 최소 버전 14는 유지한다. 최종 앱·Helper의 요구 버전은 15.1이다.
- Debug/Release 산출물에 `Scripts/verify-macos-support.sh`를 실행하여
  Info.plist 15.1, 앱·Helper Mach-O minos 15.1, arm64를 오케스트레이터가 재확인했다.
- 새 Sol 독립 리뷰의 XCTest 가용성 지적을 반영했다. 26 전용 테스트는 15.1에서 XCTSkip한다.
- 변경 후 전체 앱 테스트 101개 통과. 15.1 타깃 빌드, Release 설정 검사와 launch smoke 통과.
- 위 검증의 실행 OS는 26.5.2 (25F84)다. 실제 15.1 기기에서 Finder AX 구조와
  입력·권한·화면 동작을 검증한 것으로 해석하지 않는다. Intel 지원은 추가하지 않았다.
