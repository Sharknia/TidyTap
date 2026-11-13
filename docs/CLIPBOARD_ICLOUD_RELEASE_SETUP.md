# TidyTap 0.3.0 iCloud 릴리즈 구성

제품 코드와 로컬 자동 검증은 실제 iCloud 사용 준비와 구분한다. unsigned/ad-hoc 프리뷰는 보관함을 사용할 수 있지만 CloudKit 구성 검사를 통과하지 않으므로 동기화 스위치를 켜면 구성 안내를 표시한다. 실제 연결 성공으로 표시하지 않는다.

## 필요한 Apple 자원

팀은 V9SQZ6B7RP, 주 앱 bundle ID는 `com.sharknia.TidyTap`이다. 주 App ID에 iCloud/CloudKit·Push Notifications를 켜고 소유한 iCloud container를 연결한다. 예시 식별자는 `iCloud.com.sharknia.TidyTap`이며, 실제 등록·연결 상태를 확인한 값을 사용한다. 다른 앱의 컨테이너를 재사용하지 않는다.

같은 App ID·container와 `Developer ID Application: HakKyeol Lee (V9SQZ6B7RP)`에 맞는 Developer ID provisioning profile이 필요하다. profile은 Xcode의 사용자 profile 위치에 설치하며 저장소에 넣지 않는다. Helper는 일반 실행 파일이므로 CloudKit entitlement/profile을 붙이지 않는다. 별도 API key나 p8 파일을 이 기능을 위해 만들 필요는 없다.

무시되는 `Config/LocalSigning.xcconfig`에 기존 서명 값과 다음 값을 연결한다. 아래 값은 설정 예시이며 현재 등록됐다는 증거가 아니다.

```xcconfig
TIDYTAP_CLOUDKIT_CONTAINER_IDENTIFIER = iCloud.com.sharknia.TidyTap
TIDYTAP_CLOUDKIT_ENTITLEMENTS = Config/TidyTap.entitlements
TIDYTAP_CLOUDKIT_PROFILE_SPECIFIER = 실제 Developer ID 프로파일 이름
```

주 앱 Release target만 entitlement/profile을 사용한다. Debug·일반 XCTest·smoke·기본 ad-hoc 프리뷰에서는 실제 CloudKit 연결을 하지 않는다. 입력 설정과 동기화 의도는 별도이며 기본 의도는OFF다.

## 스키마 준비와 수용

최종 모델은 `ClipboardLibraryStore.managedObjectModel()`의 LibraryHistory/LibraryPin이다. Development용 서명·시험 계정·별도 합성 store를 사용하는 일회성 도구에서 이 모델로 `NSPersistentCloudKitContainer`를 로드한 뒤 `initializeCloudKitSchema()`를 실행해 개발 스키마를 준비한다. 기존 제품 SQLite를 schema initializer에 전달하지 않는다. 이 API는 제품 정상 실행 경로에 넣지 않았다.

CloudKit Console에서 생성된 Core Data record type/field를 대조한 뒤 검토된 최종 스키마를 Production에 배포한다. probe의 ProbeEntry type을 제품 컨테이너에 배포하지 않는다. Production type/field는 추가 위주로 관리하며 지원 구·신 모델 조합을 확인한다. [Apple 모델 제약·스키마 승격](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit), [미러링 진단](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer).

최종 서명 후보에서 최초 전송, OFF/ON, 삭제·고정 충돌, 계정 A→B, Helper 단독 수집, 두 Mac 반영, 용량·지원 OS를 확인한다. 관찰 가능한 CloudKit 이벤트 종료와 컨테이너 해제는 코드의 종료 조건이며, SDK 내부 송수신 종료 보장은 이 실제 수용에서 검증해야 한다.

## 빌드·검사

```sh
zsh Scripts/verify-release-build-settings.sh --require-local
python3 Scripts/verify-clipboard-cloudkit-configuration.py /검사할/TidyTap.app --require-cloudkit
```

검사기의 합성 회귀시험은 `python3 Scripts/test-clipboard-cloudkit-configuration.py`로 재실행한다. 실제 코드 서명/CloudKit을 호출하지 않는다.

두 번째 명령은 실제 앱 서명·entitlement·profile 메타데이터와 팀·기한·APNs를 검사한다. profile 원문은 출력하지 않는다. CMS 메타데이터 대조가 서버 동기화·Production 스키마·OS 실행 수용을 대신하지 않는다. 공개 release 스크립트와 artifact verifier에도 이 검사를 연결했다.

실제 자원 설정·스키마 승격·서명 후보의 두 Mac 시험은 이번 자동 시험에 포함하지 않았다. 공개 릴리즈·설치본 교체도 수행하지 않는다. 기존 공증 프로필 `claude-session-notary`를 쓰는 공개 배포는 별도 릴리즈 요청에서 진행한다.
