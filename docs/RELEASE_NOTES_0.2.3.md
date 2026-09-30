# TidyTap 0.2.3

- 버전 0.2.3, 빌드 11. Apple Silicon 및 macOS 15.1 이상을 대상으로 한다.
- 설정 화면의 스크롤 콘텐츠를 제목 표시줄 아래의 안전 영역에 제한했다. 창 배경은 시스템 표준 배경을 사용한다.
- 클립보드 히스토리에 `전체 / 이미지` 필터를 추가했다. 이미지 모드에서는 텍스트 검색을 비활성화하고, 전체로 돌아오면 검색어와 검색 초점을 복원한다.
- 필터 전환·새 복사·삭제 후에도 현재 결과에 맞는 선택과 미리보기를 유지한다. 진행 중인 이전 검색 결과가 이미지 목록을 덮지 않으며, 용량 초과 보호 상태에서 다른 기록을 자동 선택하지 않는다.
- macOS 26 이상에서는 검색창과 조화되는 시스템 캡슐 형태를 사용한다. 두 선택칸은 동일 폭이고, 이전 지원 OS에서는 기존 시스템 형태를 유지한다.

## 검증 범위

최종 main 커밋 `bd891c5`에서 macOS 26.5.2·Xcode 26.6의 앱 테스트 165개·입력 엔진 테스트 119개 및 단독 격리 실행 검사가 통과했다. Astra 후속 적대적 리뷰에서 확정한 코드 회귀·호환성·레이아웃 결함은 없다. 공개 DMG를 이 커밋에서 새로 빌드해 Developer ID 서명·Apple 공증·Gatekeeper·체크섬·앱/Helper 내용 검사를 통과했다. 공개된 파일을 다시 다운로드해 체크섬이 일치하는 것도 확인했다. 앞선 로컬 빌드 11 설치에서는 설정·권한 보존을 확인했다.

실제 상단바 수동 드래그, 한글 IME 필터 전환, VoiceOver, 밝은 외관의 추가 확인 및 외부 앱의 최종 입력 결과는 전체 통과로 처리하지 않았다. 상세 코드·단위 검증과 실제 사용 검증의 경계는 [작업계획 및 검증 기록](SETTINGS_SCROLL_AND_CLIPBOARD_IMAGE_FILTER_PLAN.md)에 남긴다. 화면 크기에 따른 상대 크기 대응은 이번 릴리스에 포함하지 않는다.


## 공개 산출물

- [GitHub Release v0.2.3](https://github.com/Sharknia/TidyTap/releases/tag/v0.2.3)
- [TidyTap-0.2.3.dmg](https://github.com/Sharknia/TidyTap/releases/download/v0.2.3/TidyTap-0.2.3.dmg)
- [SHA-256 파일](https://github.com/Sharknia/TidyTap/releases/download/v0.2.3/TidyTap-0.2.3.dmg.sha256)
- 태그 커밋: `bd891c5ebe33bcaeffdce4c5218712bf9d894c5b`
- SHA-256: `6292004219209a3f0493daad7d4f45da93252a5a6e32ed0068c726888f49582f`

공개 파일 게시 후 서명된 Sparkle 0.2.3/빌드 11 피드를 반영한다. 기존 설치본에서 다운로드·교체·재실행하는 자동 업데이트 전체 흐름은 별도 실사용 검증이 남아 있다.
