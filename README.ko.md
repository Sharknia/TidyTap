# TidyTap

[![릴리스](https://img.shields.io/github/v/release/Sharknia/TidyTap?include_prereleases&label=release)](https://github.com/Sharknia/TidyTap/releases)
[![에셋 다운로드](https://img.shields.io/github/downloads/Sharknia/TidyTap/total?label=asset%20downloads)](https://github.com/Sharknia/TidyTap/releases)
[![언어](https://img.shields.io/badge/languages-%ED%95%9C%EA%B5%AD%EC%96%B4%20%2F%20English-2ea44f)](README.ko.md)
[![라이선스: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)

TidyTap은 macOS 입력 불편 세 가지를 해결하는 작은 유틸리티입니다.

- Caps Lock을 대문자 고정 없이 두 입력 소스 전환키(F18 매핑)로 사용합니다.
- 모든 비연속 line-based 마우스 휠 이벤트의 세로 방향을 반전하고 트랙패드 스크롤은 그대로 둡니다. `0.1.0`에서 물리 검증 및 지원을 보장하는 장치는 VXE Mouse 1K Dongle뿐이며, 구현에 제조사 필터는 없습니다.
- 활성 Safari 또는 Finder 창에서 마우스 버튼 3/4를 뒤로/앞으로 이동키로 사용합니다.

세 기능은 각각 토글할 수 있습니다. 설정 창에는 **로그인할 때 시작** 옵션도 있습니다. 손쉬운 사용과 입력 모니터링은 **TidyTap**에 허용하면 됩니다. Worker는 같은 앱 내부 실행 파일이며 별도의 권한 대상이 아닙니다. TidyTap은 Dock에 표시되는 일반 앱이며, `Command-Q`로 설정 앱을 종료해도 켜진 helper는 계속 실행됩니다.

## 지원 범위와 상태

개발 빌드는 MacBook Pro `Mac15,6`(Apple M3 Pro)와 macOS 26.6.2(`25G83`)에서 확인 중입니다. 현재 물리 검증은 스크롤 장치 분류(VXE와 내장·Magic Trackpad 구분)와 VXE 측면 버튼이 Core Graphics 버튼 3/4로 보고되는지에 한정됩니다. Caps Lock 입력 소스 백업·복원, 권한 허용·회수, 휠 및 Safari/Finder 탐색 통합 동작, helper 수명·로그인 동작, 지원 제거 순서는 아직 통합 라이브 검증이 남아 있으며 완료를 주장하지 않습니다. UI는 한국어와 영어를 지원합니다. 다른 Mac이나 macOS 버전에서 실행될 수는 있지만 `0.1.0` 호환성을 보장하지 않습니다.

상태: `0.1.0` 릴리스. 로컬 TidyTap Release 스킬은 이후 릴리스에 사용할 수 있습니다.

[MVP 작업 계획](docs/MVP_PLAN.md)과 [English README](README.md)도 참고하세요.

## 권한

- Caps Lock 입력 소스 전환: 손쉬운 사용 및 입력 모니터링 권한이 필요하지 않습니다.
- 마우스 휠 반전: 손쉬운 사용과 입력 모니터링 권한이 모두 필요합니다.
- Safari/Finder 측면 버튼: 손쉬운 사용 권한만 필요합니다.

필요한 권한이 없거나 나중에 회수되면 해당 기능은 적용되지 않고 설정 창에 손쉬운 사용 또는 입력 모니터링을 명확히 표시합니다. 권한 버튼을 누르면 실제로 권한을 사용하는 내장 helper가 macOS 공개 API로 권한을 요청하며, TidyTap으로 돌아오면 꺼진 기능을 다시 켜지 않은 채 helper의 현재 권한 상태만 갱신합니다. 지원하지 않는 앱의 측면 버튼과 연속 또는 분류할 수 없는 스크롤은 원래 입력 그대로 통과합니다.

## 설치 및 실행

`v0.1.0` 릴리스는 버전이 일치하는 main 태그에서 준비했습니다. 개발 중에는 앱을 로컬에서 빌드한 뒤 결과물을 여세요.

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
```

앱은 Dock에 표시되는 일반 macOS 앱으로 설정 창 하나를 엽니다. 핵심 기능을 켜면 내장된 백그라운드 전용 `TidyTapHelper`가 실행되고 저장된 설정을 적용합니다. **로그인할 때 시작**은 다음 로그인부터 helper를 등록합니다. 이 옵션을 끄면 자동 시작을 해제하고 수동 실행한 Worker에서 켜진 기능을 계속 처리합니다. 세 기능을 모두 끄면 helper는 소유한 상태를 복원하고 event tap을 제거한 뒤 종료합니다.

## 제거 및 복원 순서

Caps Lock 백업과 helper를 안전하게 복원하려면 반드시 다음 순서를 따르세요.

1. 세 핵심 기능과 **로그인할 때 시작**을 모두 끕니다.
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

앱 진입점을 변경한 뒤에는 프로세스 단위 launch smoke도 실행합니다.

```sh
Scripts/launch-smoke.sh
```

이 스크립트는 unsigned Release 앱을 빌드해 ad-hoc 서명하고, 격리된 all-off
설정으로 앱과 helper를 실행합니다. 설정 창 하나, helper 시작·종료, 실제 입력
및 운영 preferences 상태가 바뀌지 않았는지를 함께 검증합니다.

서명 archive가 필요하면 `Config/LocalSigning.xcconfig.example`을 gitignore 대상인 `Config/LocalSigning.xcconfig`으로 복사하고 실제 Developer ID 정보를 입력하세요. 서명 값은 커밋하지 마세요.

## 개인정보 보호와 제한사항

TidyTap은 네트워크 요청을 하지 않으며 텔레메트리, 분석, 클라우드 동기화, 업데이트 확인, 키 입력·마우스 기록을 제공하지 않습니다. 이벤트 콜백은 필요한 버튼·스크롤 값만 메모리에서 즉시 처리하고 저장하지 않습니다.

MVP에는 사용자 지정 매핑, 프로필, 수평 스크롤 반전, 속도·가속 조절, Safari/Finder 외 앱 탐색, 비활성 창 탐색, 메뉴 막대 항목, 별도 제거 프로그램, helper 자동 재시작이 없습니다. 입력 소스 목록 관리도 범위 밖이며, 위 제거 순서를 사용해야 합니다.

## 연락처

- 이메일: [zel@kakao.com](mailto:zel@kakao.com)
- GitHub: [Sharknia/TidyTap](https://github.com/Sharknia/TidyTap)

## 라이선스

TidyTap은 [MIT 라이선스](LICENSE)로 배포됩니다.
