import XCTest
@testable import AllnighterCore

final class LocalRuntimeAdvisoryTests: XCTestCase {
  func testNilG1IsUnknownNotFail() {
    XCTAssertEqual(
      LocalRuntimeAdvisory.reason(g1Passed: nil, servedContextWindow: nil, tagObservedInPS: false),
      LocalRuntimeAdvisory.g1Unknown
    )
  }

  func testObservedG1FailUsesTableString() {
    XCTAssertEqual(
      LocalRuntimeAdvisory.reason(g1Passed: false, servedContextWindow: 131_072, tagObservedInPS: true),
      LocalRuntimeAdvisory.g1Failed
    )
  }

  func testLowServedWindowOnlyWhenG1ObservedPass() {
    XCTAssertEqual(
      LocalRuntimeAdvisory.reason(g1Passed: true, servedContextWindow: 4096, tagObservedInPS: true),
      LocalRuntimeAdvisory.servedWindowBelowFloor(4096)
    )
  }

  func testWindowUnobservedWhenG1PassAndNoPSRow() {
    XCTAssertEqual(
      LocalRuntimeAdvisory.reason(g1Passed: true, servedContextWindow: nil, tagObservedInPS: false),
      LocalRuntimeAdvisory.windowUnobserved
    )
  }

  func testNoAdvisoryWhenG1PassAndWindowAboveFloor() {
    XCTAssertNil(
      LocalRuntimeAdvisory.reason(g1Passed: true, servedContextWindow: 131_072, tagObservedInPS: true)
    )
  }

  func testWindowUnobservedUsesPossessive() {
    XCTAssertTrue(LocalRuntimeAdvisory.windowUnobserved.contains("model's context size"))
    XCTAssertFalse(LocalRuntimeAdvisory.windowUnobserved.contains("this model context"))
  }

  func testContextSizeFormatsAsKNotRawTokens() {
    XCTAssertEqual(LocalRuntimeAdvisory.formatContextSize(32_768), "32K")
    XCTAssertEqual(LocalRuntimeAdvisory.formatContextSize(65_536), "64K")
    XCTAssertEqual(LocalRuntimeAdvisory.formatContextSize(4_096), "4K")
    XCTAssertEqual(LocalRuntimeAdvisory.formatContextSize(1000), "1000")
    XCTAssertTrue(LocalRuntimeAdvisory.servedWindowBelowFloor(32_768).contains("32K"))
    XCTAssertFalse(LocalRuntimeAdvisory.servedWindowBelowFloor(32_768).contains("32768"))
  }
}
