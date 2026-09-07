# Finder 선택 항목 화면 좌표 검사

2026-09-07, macOS 26.5.2 (25F84). 제품 변경 없이 임시 Alpha.txt/Beta.txt로 확인했다.

```sh
swiftc Spikes/FinderSelectionFrameProbe/main.swift -o /tmp/finder-selection-frame
/tmp/finder-selection-frame
```

접근성 권한이 있는 실행 환경에서 Finder의 현재 초점과 선택 요소를 읽는다.
이 검사 코드는 키 입력·파일 복사·이동·알림 표시를 하지 않는다.
검사 도구가 전면으로 돌아와도 Finder를 읽을 수 있도록 전면 앱 제한은 생략했다.
제품은 별도로 전면 Finder와 파일 목록 초점을 확인해야 한다.

| 보기 | 선택 접근 경로 | 관측한 화면 사각형 (x, y, width, height) |
|---|---|---|
| 목록 | AXSelectedRows → 첫 AXCell → 파일명 AXTextField | 2452, 381, 60, 18 |
| 아이콘 | AXSelectedChildren → AXGroup | 2434, 371, 64, 64 |
| 계층 | AXSelectedChildren → AXGroup → 파일명 AXTextField | 2708, 354, 60, 18 |
| 갤러리 | AXSelectedChildren → AXGroup | 2414, 675, 48, 48 |

모두 AXPosition과 AXSize를 AXValue로 읽었다. 목록은 행 전체 좌표도 반환하지만
너비가 731이므로 파일 근처 알림에는 파일명 또는 첫 셀의 좌표가 더 적합하다.
아이콘 좌표는 파일명까지 포함하는 전체 선택 영역이 아니라 아이콘 사각형이었다.
갤러리는 큰 미리보기 대신 하단 썸네일 좌표다. 실제 화면에서 창 좌측 상단
(2217, 295)에 대한 상대 위치 (197, 380)와 선택 썸네일 위치가 맞음을 확인했다.

갤러리에서 두 파일을 선택하면 AXSelectedChildren 2개와 서로 다른 좌표가 반환된다.
원본 출력은 evidence/에 있다. 다중 선택에서 어떤 항목 옆에 알림을 놓을지는 별도 UX 결정이다.

결론: 네 보기에서 선택 파일 근처에 알림을 배치할 좌표를 얻을 수 있다.
향후 제품 적용 시 AX 화면 좌표와 AppKit 좌표 변환, 화면/창 경계 안으로 위치 조정,
스크롤로 가려진 항목 제외, 표시 시점의 초점/선택 변경을 처리해야 한다.
좌표가 없거나 표시 영역 밖이면 위치를 추측하지 않는다.
현재 실험은 한 화면 배치의 안정된 선택 상태에 한정하며 macOS 15.1, 다중 모니터 간 이동,
스크롤 중 좌표 갱신, 대량 선택과 알림 UI는 검증하지 않았다.
