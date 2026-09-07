import XCTest
@testable import TidyTapInputEngine

final class FinderSystemAdaptersTests: XCTestCase {
    func testAXQueryBudgetCapsEachCallAndRejectsWorkAfterOverallDeadline() {
        let budget = AXQueryBudget(startedAt: 10, total: 0.03, perCall: 0.005)

        XCTAssertEqual(budget.timeout(at: 10) ?? 0, 0.005, accuracy: 0.000_001)
        XCTAssertEqual(budget.timeout(at: 10.028) ?? 0, 0.002, accuracy: 0.000_001)
        XCTAssertNil(budget.timeout(at: 10.03))
        XCTAssertNil(budget.timeout(at: 10.04))
    }
}
