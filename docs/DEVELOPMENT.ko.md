# 개발 및 검증 기록

[사용자 안내로 돌아가기](../README.ko.md)

## 빌드와 테스트

Apple Silicon Mac과 Swift 6을 지원하는 전체 Xcode 설치가 필요합니다. 앱의 대상 OS는 macOS 15.1 이상입니다. 아래 명령은 저장소 루트에서 실행하세요. 문서 확인에는 Xcode 26.6을 사용했으며 최소 Xcode 버전을 뜻하지는 않습니다.

대상과 scheme 확인:

```sh
xcodebuild -project TidyTap.xcodeproj -list
```

서명 자격 증명 없이 빌드:

```sh
xcodebuild -project TidyTap.xcodeproj -scheme TidyTap -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/TidyTap.app
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

## 기존 검증 범위 기록


- 확인: Apple M3 Pro MacBook Pro의 macOS 26.5.2 환경, 0.1.3 릴리스 launch-smoke와 시스템 상태 미변경 검사.
- 남은 실제 실행 검증: macOS 15.1, Caps Lock 백업·복원, 권한 변경, 휠·탐색 통합 동작, 로그인·helper 수명, 제거 순서.
- Finder 개별 결과는 [Finder 검증 기록](FINDER_CUT_PASTE_VALIDATION.md)을 참고하세요.

프로젝트 버전: `0.1.3`. 공개된 버전과 서명된 다운로드 파일은 [GitHub Releases](https://github.com/Sharknia/TidyTap/releases)에서 확인하세요.

[MVP 작업 계획](MVP_PLAN.md)과 [English README](../README.md)도 참고하세요.

## 구현 상세


- Caps Lock을 대문자 고정 없이 두 입력 소스 전환키(F18 매핑)로 사용합니다.
- 모든 비연속 line-based 마우스 휠 이벤트의 세로 방향을 반전하고 트랙패드 스크롤은 그대로 둡니다. 구현에 제조사 필터는 없으며, 기기별 실제 동작 확인은 별도로 필요합니다.
- 휠 단계 크기를 방향 반전과 별도로 켜고 조절합니다(논리적 1-10줄, 기본 3줄). 기본은 꺼짐이며 꺼도 선택한 크기를 기억합니다. 비연속 단일 단계 입력에 적용하고 더 큰 입력의 크기는 보존합니다. 모든 마우스·속도에서 가속을 완전히 제거한다는 의미는 아니며, 물리 검증은 별도로 남아 있습니다.
- 활성 Safari 또는 Finder 창에서 마우스 버튼 3/4를 뒤로/앞으로 이동키로 사용합니다.
- Finder 파일 목록에서 `⌘X`로 잘라내고 `⌘V`로 이동합니다. 일반 `⌘C → ⌘V`는 복사입니다. 선택 항목 옆에 약 1초 동안 ‘이동 준비됨’ 또는 ‘복사 준비됨’을 표시합니다. 기본은 꺼짐이며 파일 이름 변경·검색 등 텍스트 입력에서는 원래 단축키를 유지합니다.

각 기능은 독립적으로 토글할 수 있습니다. 설정 창에는 **로그인할 때 시작** 옵션도 있습니다. 마우스 기능을 사용하려면 **TidyTap**에 손쉬운 사용 권한을 허용하세요. Worker는 같은 앱 내부 실행 파일이며 별도의 권한 대상이 아닙니다. TidyTap은 Dock에 표시되는 일반 앱이며, `Command-Q`로 설정 앱을 종료해도 켜진 helper는 계속 실행됩니다.

Finder 잘라내기는 0.1.3 릴리스에 포함된 기능입니다. 이동 명령을 보내면 기억을 지우므로 Finder에서 이동을 취소하거나 실패하면 다시 `⌘X`가 필요합니다. 바탕화면·다른 파일 관리자·우클릭 붙여넣기는 변환하지 않습니다. [설계](FINDER_CUT_PASTE_PLAN.md)와 [검증 범위](FINDER_CUT_PASTE_VALIDATION.md)를 참고하세요.


[Architecture](ARCHITECTURE.md) · [Permissions](PERMISSION_OWNERSHIP.md) · [Release workflow](RELEASE.md) · [Wheel step validation](WHEEL_STEP_SIZE_VALIDATION.md)
