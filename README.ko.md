# TidyTap

TidyTap은 macOS 입력 불편 세 가지를 해결하는 작은 유틸리티입니다.

- Caps Lock을 대문자 고정 없이 두 입력 소스 전환키(F18 매핑)로 사용합니다.
- 지원하는 VXE 마우스의 세로 line-based 휠만 반전하고, 내장 트랙패드와 Magic Trackpad는 그대로 둡니다.
- 활성 Safari 또는 Finder 창에서 마우스 버튼 3/4를 뒤로/앞으로 이동키로 사용합니다.

세 기능은 각각 토글할 수 있습니다. 설정 창에는 **로그인할 때 시작**과 **메뉴 막대에 표시** 옵션도 있습니다. 메뉴 막대 항목에는 **TidyTap 열기**만 표시되며 기능 토글은 Dock 앱에서 합니다. `Command-Q`로 설정 앱을 종료해도 켜진 helper는 계속 실행됩니다.

## 지원 범위와 상태

검증 환경은 MacBook Pro `Mac15,6`(Apple M3 Pro), macOS 26.6.2(`25G83`), VXE Mouse 1K Dongle, 내장 트랙패드, Apple Magic Trackpad입니다. UI는 한국어와 영어를 지원합니다. 다른 Mac이나 macOS 버전에서 실행될 수는 있지만 `0.1.0` 호환성을 보장하지 않습니다.

상태: 개발 빌드. 공증된 배포용 `0.1.0` 릴리스는 아직 없습니다.

[MVP 작업 계획](docs/MVP_PLAN.md)과 [English README](README.md)도 참고하세요.

## 권한

- Caps Lock 입력 소스 전환: 손쉬운 사용 및 입력 모니터링 권한이 필요하지 않습니다.
- 마우스 휠 반전: 손쉬운 사용과 입력 모니터링 권한이 모두 필요합니다.
- Safari/Finder 측면 버튼: 손쉬운 사용 권한만 필요합니다.

필요한 권한이 없거나 나중에 회수되면 해당 기능은 적용되지 않고 설정 창에 macOS 시스템 설정으로 가는 안내가 표시됩니다. 지원하지 않는 앱의 측면 버튼과 마우스로 확실히 분류할 수 없는 스크롤은 원래 입력 그대로 통과합니다.

## 설치 및 실행

현재 패키지 릴리스는 없습니다. 앱을 로컬에서 빌드한 뒤 결과물을 여세요.

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
```

앱은 Dock에 표시되는 일반 macOS 앱으로 설정 창 하나를 엽니다. 핵심 기능이나 메뉴 막대 옵션을 켜면 내장된 백그라운드 전용 `TidyTapHelper`가 실행되고 저장된 설정을 적용합니다. **로그인할 때 시작**은 다음 로그인부터 helper를 등록합니다. 이 옵션을 끄면 자동 시작만 해제되고 현재 helper는 멈추지 않습니다. 세 기능과 메뉴 막대 표시를 모두 끄면 helper는 소유한 상태를 복원하고 event tap을 제거한 뒤 종료합니다.

## 제거 및 복원 순서

Caps Lock 백업과 helper를 안전하게 복원하려면 반드시 다음 순서를 따르세요.

1. 세 핵심 기능, **로그인할 때 시작**, **메뉴 막대에 표시**를 모두 끕니다.
2. Caps Lock 백업이 복원되고 helper가 종료됐는지 확인합니다.
3. TidyTap을 종료하고 `TidyTap.app`을 삭제합니다.

앱을 먼저 삭제한 경우 자동 복원은 지원하지 않습니다. TidyTap은 타사 유틸리티를 제거하지 않습니다. 검증 전 Scroll Reverser나 개인용 Caps Lock LaunchAgent 같은 충돌 도구는 직접 종료하거나 비활성화하세요.

## 개발

대상과 scheme 확인:

```sh
xcodebuild -project TidyTap.xcodeproj -list
```

서명 자격 증명 없이 빌드:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

앱 테스트와 Swift 패키지 테스트:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
swift test --package-path Packages/TidyTapInputEngine
```

서명 archive가 필요하면 `Config/LocalSigning.xcconfig.example`을 gitignore 대상인 `Config/LocalSigning.xcconfig`으로 복사하고 실제 Developer ID 정보를 입력하세요. 서명 값은 커밋하지 마세요. 현재 저장소에는 공증 및 공개 릴리스가 없습니다.

## 개인정보 보호와 제한사항

TidyTap은 네트워크 요청을 하지 않으며 텔레메트리, 분석, 클라우드 동기화, 업데이트 확인, 키 입력·마우스 기록을 제공하지 않습니다. 이벤트 콜백은 필요한 버튼·스크롤 값만 메모리에서 즉시 처리하고 저장하지 않습니다.

MVP에는 사용자 지정 매핑, 프로필, 수평 스크롤 반전, 속도·가속 조절, Safari/Finder 외 앱 탐색, 비활성 창 탐색, 메뉴 막대 기능 토글, 별도 제거 프로그램, helper 자동 재시작이 없습니다. 입력 소스 목록 관리도 범위 밖이며, 위 제거 순서를 사용해야 합니다.

## 연락처

- 이메일: [zel@kakao.com](mailto:zel@kakao.com)
- GitHub: [Sharknia/TidyTap](https://github.com/Sharknia/TidyTap)
