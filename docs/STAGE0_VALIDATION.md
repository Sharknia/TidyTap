# TidyTap 단계 0 검증 기록

검증일: 2026-09-05  
환경: MacBook Pro `Mac15,6`, Apple M3 Pro, macOS 26.6.2 (`25G83`)

원시 이벤트 로그는 저장하지 않았다. 아래 값은 `InputEventProbe`가 종료 시 출력한 집계만 기록한 것이다.

## 장치 분류

| 장치 | 관찰 결과 | 판정 |
| --- | --- | --- |
| VXE Mouse 1K Dongle | `discrete-mouse=659`, `trackpad=0`, `unknown=0` | 통과 |
| MacBook 내장 트랙패드 | `discrete-mouse=0`, `trackpad=6059`, `unknown=18` | 통과 |
| Apple Magic Trackpad | `discrete-mouse=0`, `trackpad=446`, `unknown=67` | 통과 |

트랙패드의 `unknown`은 반전하지 않고 통과시키는 연속/종료 이벤트다. 두 트랙패드 모두 마우스로 오분류된 이벤트가 없으므로 트랙패드 방향 보존 조건을 충족한다.

## 측면 버튼 식별

- VXE 물리 뒤로/앞으로 버튼에서 Core Graphics `button 3`, `button 4`가 각각 관찰됐다.
- 버튼 이벤트는 내장 트랙패드 검증 중 별도로 발생했으며 스크롤 분류 상태에는 관여하지 않는다.

## 아직 남은 단계 0 항목

- Caps Lock 적용/조건부 복원의 제품 통합 검증
- Safari/Finder 측면 버튼 탐색의 제품 통합 검증
- 설정 앱 종료 후 helper 독립 실행과 설정 IPC 검증
- 권한 거부, 허용, 회수 상태 검증

위 항목은 실제 TidyTap 통합 빌드에서 수행한다. 사용자 물리 입력이 필요한 시험은 시작 전에 내용과 시간을 안내하고 명시적인 시작 확인을 받은 뒤 실행한다.
