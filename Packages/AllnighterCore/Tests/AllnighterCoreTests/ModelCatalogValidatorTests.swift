import XCTest
@testable import AllnighterCore

final class ModelCatalogValidatorTests: XCTestCase {

    func testBundledCatalogAndOverlayValidateClean() {
        let summary = ModelCatalogValidator.validate()
        XCTAssertTrue(summary.ok, summary.problems.joined(separator: "; "))
        XCTAssertGreaterThan(summary.driverCount, 0)
        XCTAssertGreaterThan(summary.modelCount, 0)
        XCTAssertGreaterThan(summary.overlayModelCount, 0)
        XCTAssertTrue(summary.problems.isEmpty)
    }
}
