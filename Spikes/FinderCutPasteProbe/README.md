# Finder cut/paste probe

제품 설정이나 Helper를 실행하지 않고 현재 입력 엔진만 켜는 수동 검증 도구다.

저장소 루트에서 빌드하고 실행한다.

```sh
swiftc \
  Packages/TidyTapInputEngine/Sources/TidyTapInputEngine/*.swift \
  Spikes/FinderCutPasteProbe/main.swift \
  -o /tmp/tidytap-finder-cut-paste-probe
/tmp/tidytap-finder-cut-paste-probe
```

Finder 파일 목록에서 `Command-X`, 다른 폴더에서 `Command-V`를 누른다. 일반
`Command-C`, 텍스트 입력 초점, Finder 밖의 앱에서는 원래 단축키가 그대로 동작해야 한다.
실행한 터미널에 접근성 및 입력 모니터링 권한이 필요하다.
