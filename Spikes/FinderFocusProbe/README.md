# Finder 초점 판별 실험

2026-09-07, macOS 26.5.2 (25F84). 실제 Finder와 임시 파일로 검사.
파일 이동, 클립보드 변경, 키 가로채기는 하지 않는다.

```sh
swiftc Spikes/FinderFocusProbe/main.swift -o /tmp/finder-focus-probe
/tmp/finder-focus-probe
```

접근성 권한이 있는 실행 환경이 필요하다. 기본 모드는 Finder가 전면이 아니면 PASS.
검사 도구 호출 시 Codex가 전면으로 돌아오므로 이번 상태별 검사는
`/tmp/finder-focus-probe --inspect-finder`로 Finder의 원본 AXFocusedUIElement를 읽었다.
이 옵션은 전면 앱 조건을 건너뛰는 진단 전용이다. 실제 키 처리에 사용하면 안 된다.

| 상태 | 원본 초점 | 결과 |
|---|---|---|
| 목록 선택 | AXOutline / ListView | ALLOW |
| 아이콘 선택 | AXList / IconView | ALLOW |
| 계층 선택 | AXList, 상위 AXBrowser / ColumnView | ALLOW |
| 갤러리 선택 | AXList / GalleryView | ALLOW |
| 위 네 보기의 이름 변경 | AXTextField / ShrinkToFit Text Field | 모두 PASS |
| 검색 | AXTextField / AXSearchField 서브역할 | PASS |
| 폴더로 이동 | AXTextField / PathTextField | PASS |

원본 로그는 evidence/에 있다. PASS는 원래 키를 전달하라는 판별 결과이며
이 프로그램 자체는 키를 전달하거나 변경하지 않는다.
초점 조회 실패도 PASS로 처리한다. 파일 목록 내부에 텍스트 필드가 존재하는지
검사하지 않고, 현재 초점 자체의 역할과 식별자를 확인한다.

이름 변경 초점이 UI 검사 도구에는 누락되었지만 원본 API에는 정상 반환되었다.
아이콘/갤러리의 원본 역할도 AXCollection이 아니라 AXList였다.

검증 범위는 안정된 화면 상태에서의 초점 분류다. 초점 조회와 실제 키 처리 사이의
경합, 빠른 연속 입력, 다른 macOS 버전, 바탕화면은 검증하지 않았다.
따라서 파일/텍스트 구분 가능성의 증빙이며 배포 가능한 단축키 구현은 아니다.
