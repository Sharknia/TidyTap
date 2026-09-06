# 휠 테스트 빌드 교체 시 Worker 불일치

## 2026-09-06 실제 관찰

사용자가 preview DMG로 앱을 교체하고 휠 단계 크기를 켰으나 토글이 어둡게 보이고 기능이 적용되지 않는다고 보고했다.

- 새 설정 앱은 22:38에 `/Applications/TidyTap.app`에서 시작했다.
- 입력 Worker는 20:45에 시작한 프로세스가 그대로 남아 있었다.
- 같은 요청 ID의 `applyStatus`는 `applied`였지만 `effectiveSettings`에 기존 네 항목만 있었으며 새 `fixedMouseWheelStepEnabled`, `mouseWheelStepLines`가 없었다.
- 디스크의 교체된 Worker 실행 파일에는 새 설정 항목이 포함되어 있었다. 디스크 파일 교체는 이미 실행 중인 프로세스를 교체하지 않는다.
- 새 Worker를 실행해도 기존 Worker가 singleton lock을 보유하므로 바로 종료됐다. 런처는 프로세스 생성만 성공하면 이 상태를 구분하지 않았다.
- 새 UI의 구형 설정 호환 디코딩은 누락된 휠 항목을 OFF/3으로 채웠다. 이 때문에 구형 응답이 성공으로 수락되고 새 토글은 다시 꺼졌다.

확인한 구형 Worker만 종료하고 설치된 앱을 다시 활성화하자 새 Worker가 실행됐다. 새 결과에는 여섯 설정 항목이 모두 포함됐으나 접근성·입력 모니터링 권한은 둘 다 거부 상태였다. 기존 초록색 표시는 구형 Worker의 결과였으며, ad-hoc preview 서명과 기존 배포 서명은 권한 관점에서 동일하지 않았다. 새 Worker는 이를 부분 적용 실패로 반환하고 두 마우스 기능을 OFF로 저장했다. Caps Lock과 로그인 설정은 유지됐다.

## 수정 방향

1. 실제 실행 중인 자사 Worker와 현재 앱 내부 Worker의 실행 파일 신원을 비교하고, 확인된 구버전만 교체한다. 버전 문자열이 같은 preview끼리도 구분한다. 동일한 singleton lock을 유지한다.
2. 고정 크기 ON 요청에 대해 새 설정의 실제 적용 상태·크기를 확인하지 못한 `applied` 응답을 성공으로 표시하지 않는다. 저장 파일의 구형 호환 디코딩은 유지한다.
3. 같은 Developer ID를 사용하는 로컬 preview 모드를 추가한다. 서명 설정 값은 기존 ignored 설정에서 읽으며 공개 릴리스·태그·설치·공증 업로드를 수행하지 않는다.

구현, 독립 리뷰, 자동 검증 결과와 최종 후보 파일은 완료 시 아래에 기록한다. 새 서명의 권한 인식 및 물리 휠 동작은 실제 설치 후 별도 확인 사항이다.

## 업데이트와 권한 유지

업데이트 자체 때문에 매번 권한을 다시 허용해야 하는 것은 아니다. macOS가 업데이트 전후 코드를 같은 앱으로 인정할 수 있는 지정 요구사항(Designated Requirement, DR)을 유지해야 한다. ad-hoc 서명은 특정 빌드에 묶여 있으므로 기존 Developer ID 배포본의 권한을 이용하는 preview로 적합하지 않았다. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

권한 유지와 Worker 갱신은 서로 다른 비교가 필요하다. TCC 관점의 앱·Worker DR은 업데이트 전후 유지하고, 런처는 현재 실행 중인 코드와 새 코드가 다른지를 확인해 구버전 프로세스를 교체해야 한다.

공식 `TidyTap-0.1.0.dmg`의 앱 및 Worker 서명 검증을 통과했으며, 비교할 DR의 SHA-256은 다음과 같다. 서명 설정 원문·개발자 식별 정보는 기록하지 않는다.

- 앱: `a0db96bf567874935dcfd97d5c0802ee10fd02ee5f3632d682d98cf2ad6d9551`
- Worker: `6c4ad2f31d5e11517572187f5cb712d69be39d0583cefb2146f47bcb5cb8cb67`

Developer ID preview 패키징을 실제 실행한 `8b322a2` 후보의 앱/Worker를 DMG에서 읽기 전용으로 열어 서명과 DR을 검사했다. 두 DR 해시가 위 정식 배포본과 모두 정확히 일치했다. 이것은 서명 신원의 연속성을 검증한 것이며, 사용자 설치 후 TCC의 실제 허용 상태와 물리 휠 동작을 검증한 것은 아니다.
