# TidyTap 0.1.1 Release Notes

## English

TidyTap 0.1.1 adds a fixed wheel-step toggle that works independently from vertical direction reversal.

- Fixed wheel step: off by default, adjustable from 1–10 logical lines, default 3.
- The selected step is remembered while the toggle is off.
- The feature applies to single-step, non-continuous mouse-wheel events; larger deltas retain their original magnitude.
- The existing direction-reversal toggle remains independent.
- The DMG opens with a compact drag-to-Applications layout, a Korean folder label and Korean installation guidance, without a separate installation text file.
- The worker update path replaces only an identified stale worker and verifies the effective settings before accepting success. Process-level replacement, restart, all-off exit, and mismatched-success handling were validated in isolated automated checks.

Known limits:

- This does not claim that all acceleration is removed for every mouse or scrolling speed.
- Physical wheel behavior, reboot behavior, and live TCC permission behavior are not claimed complete here.
- The supported target remains the VXE Mouse 1K Dongle; prior physical validation covers classification and button reports, not the new fixed-step behavior. The implementation does not filter by vendor.
- Public DMG assets are published only after Developer ID signing and Apple notarization verification; a SHA-256 sidecar accompanies the DMG.

## 한국어

TidyTap 0.1.1은 세로 방향 반전과 독립적으로 사용할 수 있는 휠 단계 크기 고정을 추가합니다.

- 휠 단계 크기 고정: 기본 꺼짐, 논리적 1–10줄, 기본 3줄.
- 토글이 꺼져 있어도 선택한 단계 크기는 기억합니다.
- 비연속 단일 단계 마우스 휠 입력에 적용하며, 더 큰 delta의 원래 크기는 유지합니다.
- 기존 휠 방향 반전 토글은 별도로 동작합니다.
- DMG 설치 창을 간결한 앱 → 응용 프로그램 배치와 한국어 안내로 정리하고, 별도 설치 안내 텍스트 파일을 제거했습니다.
- Worker 갱신 경로는 식별된 오래된 Worker만 교체하고 실제 적용 설정을 확인한 뒤 성공을 수락합니다. 프로세스 교체, 재시작, 모든 기능 OFF 종료, 불일치 성공 응답 차단은 격리된 자동 검사로 검증했습니다.

알려진 제한:

- 모든 마우스와 스크롤 속도에서 가속을 완전히 제거한다고 주장하지 않습니다.
- 실제 휠 동작, 재부팅 동작, 실시간 TCC 권한 동작은 이 문서에서 완료를 주장하지 않습니다.
- 지원 대상은 VXE Mouse 1K Dongle입니다. 기존 물리 검증은 장치 분류와 버튼 보고에 한정되며, 새 단계 크기 동작의 검증을 뜻하지 않습니다. 구현에 제조사 필터는 없습니다.
- 공개 DMG는 Developer ID 서명과 Apple 공증 검증 후 SHA-256 체크섬 파일과 함께 게시합니다.
