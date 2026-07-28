import XCTest
@testable import AllnighterCLI
import AllnighterCore

final class CatalogValidateCLITests: XCTestCase {

    func testHelpTextIncludesCatalogValidate() {
        let text = CLIUsage.usageText(for: "catalog validate")
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("catalog validate") == true)
    }

    func testBundledValidateSummaryIsJSONEncodable() throws {
        let summary = ModelCatalogValidator.validate()
        let data = try CoreJSON.encode(summary)
        let decoded = try CoreJSON.decode(ModelCatalogValidator.Summary.self, from: data)
        XCTAssertEqual(decoded, summary)
    }
}
