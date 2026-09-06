# 단일 앱 권한과 독립 Worker

## 결정

설정 UI와 입력 처리는 서로 다른 프로세스로 유지하되, 권한 주체는 `com.sharknia.TidyTap` 하나로 통일한다.

```text
TidyTap.app/
  Contents/MacOS/TidyTap                 설정 UI, Command-Q로 종료
  Contents/MacOS/TidyTapHelper           입력 Worker, CFRunLoop
  Contents/Library/LaunchAgents/
    com.sharknia.TidyTap.Agent.plist     로그인 시 같은 Worker 실행
```

- 일반 실행은 `Process`로 앱 내부 실행 파일을 시작한다.
- 로그인 실행은 `SMAppService.agent`를 사용한다. plist의 `BundleProgram`은 앱 내부 상대 경로이며 `AssociatedBundleIdentifiers`는 TidyTap을 가리킨다.
- Worker는 `NSApplication`을 만들지 않는다. 같은 앱 번들의 두 번째 앱 인스턴스로 등록되면 LaunchServices가 설정 창 재실행을 Worker로 보내는 문제가 생기기 때문이다.
- 사용자별 `flock`으로 입력 엔진을 하나만 실행한다. 프로세스 종료 시 커널이 잠금을 해제한다.
- 설정 창이 처음 열리거나 전면으로 돌아올 때 Worker의 실제 권한을 읽는다. 사용자가 권한 버튼을 누를 때만 권한을 요청한다.
- 0.0.2의 중첩 로그인 앱 등록과 실행 중인 구형 Helper를 전환 시 정리한다.

## 이전 실패의 직접 원인

macOS 26.6.2에서 같은 Developer ID로 서명된 메인 앱과 중첩 Helper 앱을 비교했다. 메인 앱은 AX/이벤트 전송/이벤트 수신 권한이 모두 허용됐지만, 중첩 Helper는 모두 미승인이었다. TCC 로그도 메인 앱과 `.Helper`를 별도의 권한 주체로 판정했다. 따라서 UI의 실패 상태 보존이나 확인 API 변경만으로는 해결되지 않았다.

별도 Helper 앱을 앱 내부 실행 파일로 바꾼 비교 실험에서는 부모 프로세스 종료 후와 ServiceManagement 실행 모두 기존 TidyTap 권한을 인식했다. 권한 초기화나 추가 허용은 하지 않았다.

## 검증 기록 (2026-09-06)

- 앱 테스트: 57개 통과. 초기 실행·전면 복귀 시 실제 Worker 조회와 요청 중복 방지를 포함한다.
- 입력 엔진 테스트: 70개 통과.
- `Scripts/launch-smoke.sh`: 설정 창, 모든 기능 off 시 종료, 중복 Worker 배제, 종료 후 잠금 해제·재실행, 실제 HID/사용자 설정 비변경 검사 통과.
- Developer ID Release archive와 설치된 앱의 서명 검증 통과. 중첩 `.app`이 없고 Worker 실행 파일과 LaunchAgent plist가 포함됨을 확인했다.
- `/Applications/TidyTap.app`에서 기존 두 마우스 권한이 모두 허용됨으로 표시됐고 사용자가 켠 세 기능 설정과 적용 성공 상태가 유지됐다.
- 마우스 기능 활성 상태에서 설정 앱 종료·재실행 후에도 기존 Worker 프로세스가 유지됐다.
- 실제 등록된 LaunchAgent를 새로 실행하고 `lsof`로 실행 파일이 `/Applications/TidyTap.app/Contents/MacOS/TidyTapHelper`임을 확인했다.

새 계정의 최초 권한 허용/회수, 실제 재부팅·로그아웃, 물리 마우스 탐색/스크롤 전체 동작은 위 검증과 구분한다. 단순히 UI가 초록색이라는 이유만으로 모든 장치 동작이 검증됐다고 보지 않는다.

## 재발 방지 확인 순서

1. 서명된 앱의 실제 설치 경로에서 권한 요청과 Worker 응답을 확인한다.
2. 설정 앱을 종료하고 다시 열어도 Worker와 설정 창이 독립적으로 동작하는지 확인한다.
3. 일반 실행뿐 아니라 등록된 LaunchAgent에서 새 프로세스를 시작해 동일 권한 주체와 실행 경로인지 확인한다.
4. 단위 테스트의 가짜 permission provider 결과를 실제 TCC 승인 검증으로 대체하지 않는다.

참고: [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [앱 내부 실행 파일과 LaunchAgent 배치](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos).
