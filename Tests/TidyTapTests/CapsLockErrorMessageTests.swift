import XCTest

@MainActor
final class CapsLockErrorMessageTests: XCTestCase {
    func testCapsLockFailuresMapToSpecificMessages() {
        let cases: [(String, String, String)] = [
            ("capsLock.invalidInputSourceCount.3", "Caps Lock input switching requires exactly two enabled input sources.", "Caps Lock 한·영 전환에는 활성화된 입력 소스가 정확히 두 개 필요합니다."),
            ("capsLock.conflict.sourceMapping", "Caps Lock already has a key mapping. Check the existing mapping before trying again.", "Caps Lock에 이미 다른 키 매핑이 있습니다. 기존 매핑을 확인한 뒤 다시 시도하세요."),
            ("capsLock.conflict.hidOwnership", "TidyTap cannot change the Caps Lock setting because another configuration owns it.", "다른 설정이 Caps Lock 관련 키보드 설정을 사용 중이어서 TidyTap이 변경할 수 없습니다."),
            ("capsLock.conflict.symbolicHotkey", "TidyTap cannot change the Caps Lock setting because another configuration owns it.", "다른 설정이 Caps Lock 관련 키보드 설정을 사용 중이어서 TidyTap이 변경할 수 없습니다."),
            ("capsLock.invalidSystemData.hidMappings", "TidyTap could not read the current Caps Lock keyboard settings.", "TidyTap이 현재 Caps Lock 키보드 설정을 읽을 수 없습니다."),
            ("capsLock.verificationFailed.symbolicHotkey60", "TidyTap could not verify the Caps Lock setting after applying it.", "TidyTap이 적용한 Caps Lock 설정을 확인할 수 없습니다."),
            ("capsLock.recoveryRequired.hidMappings", "Caps Lock changes need to be restored before you continue.", "계속하기 전에 Caps Lock 변경 사항을 복원해야 합니다.")
        ]

        for (language, bundle, expectedIndex) in [("en", localizedBundle(language: "en"), 1), ("ko", localizedBundle(language: "ko"), 2)] {
            for values in cases {
                XCTAssertEqual(
                    TidyTapStrings.capsLockApplyMessage(for: makeStatus(errorCode: values.0), bundle: bundle),
                    expectedIndex == 1 ? values.1 : values.2,
                    "\(language): \(values.0)"
                )
            }
        }
    }

    func testCapsLockRollbackRecoveryWithOriginalEventTapFailureUsesRecoveryMessage() {
        for errorCode in ["lifecycle.rollbackFailed.capsLock", "lifecycle.rollbackFailed.eventTap.capsLock"] {
            let status = TidyTapApplyStatus(
                applyRequestID: UUID(),
                outcome: .recoveryRequired,
                failedComponent: .eventTap,
                errorCode: errorCode
            )

            XCTAssertEqual(TidyTapStrings.capsLockApplyMessage(for: status, bundle: localizedBundle(language: "en")), "Caps Lock changes need to be restored before you continue.")
            XCTAssertEqual(TidyTapStrings.capsLockApplyMessage(for: status, bundle: localizedBundle(language: "ko")), "계속하기 전에 Caps Lock 변경 사항을 복원해야 합니다.")
        }
    }

    func testDoesNotReplaceGeneralErrorsOrNonTerminalCapsLockStatuses() {
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: makeStatus(
            errorCode: "capsLock.commandFailed"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .partiallyApplied,
            failedComponent: .capsLock,
            errorCode: "capsLock.invalidSystemData.hidMappings"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .failed,
            failedComponent: .eventTap,
            errorCode: "capsLock.invalidSystemData.hidMappings"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .recoveryRequired,
            failedComponent: .eventTap,
            errorCode: "lifecycle.rollbackFailed.eventTap"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .recoveryRequired,
            failedComponent: .eventTap,
            errorCode: "lifecycle.rollbackFailed.capsLockSettings"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .recoveryRequired,
            failedComponent: .capsLock,
            errorCode: "lifecycle.rollbackFailed.eventTap"
        )))
        XCTAssertNil(TidyTapStrings.capsLockApplyMessage(for: TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .failed,
            failedComponent: .eventTap,
            errorCode: "lifecycle.rollbackFailed.capsLock"
        )))
    }

    private func makeStatus(errorCode: String) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .failed,
            failedComponent: .capsLock,
            errorCode: errorCode
        )
    }

    private func localizedBundle(language: String) -> Bundle {
        let resources = Bundle(for: Self.self)
        guard let path = resources.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else {
            return resources
        }
        return localized
    }
}
