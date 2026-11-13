# Clipboard Core Data 로컬 probe

TidyTap 0.3.0의 관리형 동기화 후보를 검토하기 전 로컬 저장·이력·두 프로세스 접근을 시험한다. 제품 앱·Helper·개인 클립보드·iCloud 계정을 사용하지 않는다. 실제 CloudKit 코드와 entitlement는 없다.

저장소 루트에서 실행한다.

```sh
bash Scripts/run-clipboard-cloudkit-probe.sh local
```

macOS15.1 이상, Xcode와 Python3가 필요하다. 현재 project는 arm64 Debug만 제공한다. 로컬 엔진 Swift package를 참조하며 외부 package를 추가하지 않는다. unsigned 시험 앱의 표시는0.3.0(1)이며 설치 제품 버전은 변경하지 않는다.

스크립트는180초 빌드·90초 실행 제한을 적용하고 실행별 새 `build/clipboard-cloudkit-probe/run.<ID>/`에 결과를 남긴다. 성공 시 launcher-summary.json에 L01~L09 passed를 출력한다. 상세 assertion은 local/results.json, 합성 SQLite·token·marker는 local/ 아래, 빌드/실행 진단은 build.log·probe.log다. 본문은 합성 fixture여도 진단 출력에 넣지 않는다.

- L01: 텍스트·RTF/HTML·PNG/TIFF·큰 binary의 byte 보존과 기존 봉투 codec 호환.
- L02: 같은 SQLite UUID·값·history를 유지한3회 재열기.
- L03: token 전 insert와 token 후 update/delete, 삭제 ID 보존.
- L04: 재열기 사이 로컬 고정/해제·삭제 보존.
- L05: 직렬화 봉투10MiB 경계 허용·1byte 초과 거부.
- L06: 독립 writer 프로세스의 token 이후 insert·author/ID·전체 값 및 해당 token의 remote notification 수신.
- L07: 로컬 타입·nil cloud options와 잘못된 cloud 인자 거부.
- L08: 잘못된 합성 SQLite load 실패·원본 보존.
- L09: 사용자 전용 권한·marker 없는 writer·UUID/kind 불일치·symlink/기존 root 거부.

실행 파일의 직접 인터페이스는 `self-test <새 빈 폴더>`, `writer <probe 폴더> <실행 UUID> <항목 UUID>`뿐이다. writer는 probe marker와 소유권/권한을 확인한다. 연결용 환경 변수는 읽지 않으며 CloudKit 구성으로 해석하지 않는다. 다른 모드/CLI는 저장소를 열기 전 exit64다.

출력은 자동 정리하지 않는다. 필요한 증거를 보존한 뒤 사용자가 해당 run 디렉터리를 지울 수 있다. 제품 Application Support나 기존 clipboard-history 디렉터리를 정리 대상으로 사용하지 않는다.

로컬 PASS는 iCloud OFF 종료·ON 병합·원격 삭제·충돌·실제 Helper·최소 지원 OS의 통과가 아니다. 전체 관문과 미실행 상태는 [Gate0 계약](../../docs/CLIPBOARD_ICLOUD_GATE0.md), [실행 현황](../../docs/CLIPBOARD_030_EXECUTION.md)을 따른다.
