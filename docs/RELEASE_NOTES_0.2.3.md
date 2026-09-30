# TidyTap 0.2.3 — 로컬 설치 후보

- 버전 0.2.3, 빌드 9. `codex/settings-scroll-image-filter` 브랜치의 로컬 설치용 빌드다.
- 설정 화면을 스크롤할 때 창 버튼과 앱 헤더가 겹치지 않도록 제목 표시줄과 콘텐츠 영역을 분리했다.
- 클립보드 히스토리에 `전체 / 이미지` 필터를 추가했다. 이미지 모드에서는 텍스트 검색을 비활성화하며, 전체로 돌아오면 검색어와 검색 초점을 복원한다.
- 필터 전환 중 오래된 검색 결과가 섞이거나 용량 초과 보호 때문에 선택하지 않은 항목이 자동 붙여넣기 대상으로 바뀌지 않도록 처리했다.

기능 코드의 앱 테스트 165개와 격리 실행 검사가 통과했고, Astra 적대적 리뷰에서 확정한 버그·회귀는 없다. 실제 한글 IME·VoiceOver·탄성 스크롤·외부 앱 삽입은 미검증 범위로 유지한다. [구현·검증 기록](SETTINGS_SCROLL_AND_CLIPBOARD_IMAGE_FILTER_PLAN.md)을 참고한다.

이번 요청은 로컬 설치다. 공개 태그·GitHub Release·Sparkle 업데이트 피드는 변경하지 않는다. 서명·공증 및 설치 결과는 아래와 같다.


## 로컬 설치 결과 — 2026-09-30

- 소스 커밋 `1adcece`에서 Release 빌드 생성. 앱 165개·입력 엔진 119개 테스트, 릴리스 빌드 설정·워크플로 검사 통과.
- 앱·Helper·Sparkle 구성요소 및 DMG의 Developer ID 서명, Apple 공증, DMG와 앱의 공증 티켓, Gatekeeper, DMG 내용·체크섬 검사 통과.
- 로컬 DMG: `build/artifacts/TidyTap-0.2.3/TidyTap-0.2.3.dmg`.
- SHA-256: `65b7f5eae8ef43c114aee68da36605a55053a2e638cb5968b5cb02b7468714bc`.
- `/Applications/TidyTap.app`에 버전 0.2.3·빌드 9 설치 후 앱과 Helper 재실행 확인. 기존 앱은 로컬 `build/verification/install-0.2.3/TidyTap-0.2.2-backup.app`에 보존.
- 기존 앱·Helper와 서명 식별 규칙 일치. 사용자 기능 설정 보존, 갱신된 권한 응답에서 손쉬운 사용·입력 모니터링 승인, 갱신된 적용 응답의 `applied` 확인.
- 실제 설치 설정 화면에서 버전 0.2.3 및 권한 승인 상태 확인. 제목 표시줄과 앱 헤더가 분리된 화면은 로컬 검증 폴더에 보관. 탄성 스크롤 및 외부 앱의 실제 붙여넣기까지 통과한 것으로 간주하지 않는다.
