# TidyTap 0.2.0

## 한국어

- 선택적으로 켜는 클립보드 히스토리를 추가했습니다. 직접 지정한 단축키로 복사한 텍스트·이미지를 검색하고 선택해 붙여넣을 수 있습니다. 설정에는 `⌥V`를 추천하지만 자동 지정하지 않습니다.
- 텍스트는 기본적으로 서식 없이 붙여넣고 `Shift+Enter`로 반대 방식을 사용할 수 있습니다. 완전히 같은 내용을 다시 복사해도 기록은 한 건만 유지하며, 히스토리 붙여넣기 키 이벤트 전송에 성공한 항목은 맨 위로 이동합니다.
- 기록은 활성화 이후부터 이 Mac에만 저장합니다. 보관 기간은 최근 복사 또는 히스토리 사용부터 7일이며 최대 100개·총 50 MiB·항목당 10 MiB입니다. 기능을 꺼도 기존 기록은 만료까지 유지되며, 저장 기록은 설정에서 별도로 삭제할 수 있습니다.
- Sparkle 기반 업데이트 확인을 추가했습니다. 새 릴리스를 자동 확인하거나 설정의 **업데이트 확인**을 사용할 수 있으며 설치에는 사용자 클릭이 필요합니다. 공개 0.1.4 이하 버전은 0.2.0 DMG를 한 번 수동 설치해야 합니다.
- 설치된 `/Applications/TidyTap.app`만 실행하도록 하고 앱·보조 프로그램의 중복 실행과 구버전 충돌을 방지합니다. 클립보드 패널의 밀도·이미지 미리보기·오류 안내를 정리하고, 시스템 외관을 따르도록 했습니다.

앱 테스트 144개, 입력 엔진 테스트 119개와 릴리스·프리뷰 DMG 절차 검사를 통과했습니다. 검증 Mac은 macOS 26.5.2입니다. 서식·이미지의 대상 앱별 삽입, 클립보드 읽기 권한 거부·복구, macOS 15.1/27의 실제 동작, Sparkle의 공개 피드 다운로드→교체→재실행은 별도 확인이 필요합니다. Helper의 붙여넣기 성공 응답은 키 이벤트 전송까지 확인하며 대상 앱의 실제 삽입 완료를 증명하지 않습니다.

Apple Silicon 및 macOS 15.1 이상을 대상으로 합니다.

## English

- Added opt-in clipboard history. Set your own shortcut to search and paste copied text and images. Settings suggests `⌥V` without assigning it automatically.
- Text pastes without formatting by default; `Shift+Enter` uses the opposite style. Identical recopies keep one entry, and an item moves to the top after the paste key event is posted successfully.
- History is stored only on this Mac after you enable it. Retention is 7 days from the latest copy or history use, limited to 100 items, 50 MiB total, and 10 MiB per item. Turning the feature off stops capture but keeps existing entries until expiry; saved history can be cleared separately in Settings.
- Added Sparkle update checks while the app runs and a **Check for Updates** button. Installing an update requires a click. Public 0.1.4 and earlier need one manual DMG replacement to gain this feature.
- Limited production execution to the installed `/Applications/TidyTap.app` and guarded against duplicate app/helper and older-copy conflicts. Refined panel density, image previews, error messages, and system appearance behavior.

Passed 144 app tests, 119 input-engine tests, and release/preview DMG workflow checks on macOS 26.5.2. Destination-app insertion of formatting and images, clipboard read-denial recovery, actual macOS 15.1/27 behavior, and Sparkle download/replace/relaunch from the public feed remain separate checks. A successful helper paste response confirms the key event was posted, not that the destination inserted the content.

Targets Apple silicon and macOS 15.1 or later.
