import XCTest
@testable import AllnighterCore
import AgentOSCLI

final class CatalogOverlayTests: XCTestCase {

    func testOverlayAcceptsPolicyFieldsOnly() {
        let valid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": {
                  "defaultOn": true,
                  "caliber": {
                    "laneTags": ["code"],
                    "capabilityTags": ["code"],
                    "strengthRank": 87
                  }
                }
              }
            }
            """.utf8
        )
        XCTAssertNoThrow(try CatalogOverlayLoader.decode(valid))

        let invalid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": {
                  "defaultOn": true,
                  "modelLabel": "nope"
                }
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(try CatalogOverlayLoader.decode(invalid)) { error in
            XCTAssertTrue(String(describing: error).contains("unknown field 'modelLabel'"))
        }
    }

    func testUnknownOverlayModelIsDiagnosedAndIgnored() throws {
        let overlay = CatalogOverlay(models: [
            "model_grok": CatalogOverlayModel(defaultOn: true),
            "model_ghost": CatalogOverlayModel(defaultOn: true),
        ])
        let catalog = try CatalogLoader.bundled()
        let diags = CatalogMerge.unknownOverlayDiagnostics(overlay: overlay, catalog: catalog)
        XCTAssertTrue(diags.contains { $0.modelId == "model_ghost" })
        XCTAssertFalse(ModelCatalog.builtIns.contains { $0.id == "model_ghost" })
    }

    func testHiddenModelSuppressesPersistedRosterEntry() throws {
        let overlay = CatalogOverlay(models: [
            "model_sonnet": CatalogOverlayModel(defaultOn: true, hidden: true),
        ])
        let roster = ModelRosterState(enabledModelIds: ["model_sonnet", "model_opus"])
        let diags = CatalogMerge.hiddenRosterDiagnostics(overlay: overlay, roster: roster)
        XCTAssertTrue(diags.contains { $0.modelId == "model_sonnet" })

        let catalog = try CatalogLoader.bundled()
        let visible = try CatalogMerge.builtInDefinitions(catalog: catalog, overlay: overlay)
        XCTAssertFalse(visible.contains { $0.id == "model_sonnet" })
    }

    func testInvalidHiddenAndDefaultOnFailsDecode() {
        let invalid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": { "defaultOn": true, "hidden": true }
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(try CatalogOverlayLoader.decode(invalid)) { error in
            XCTAssertTrue(String(describing: error).contains("hidden and defaultOn"))
        }
    }

    func testOnlyGeminiIsFreshAntigravityDefault() {
        let agy = ModelCatalog.builtIns.filter { $0.driverId == "antigravity" }
        XCTAssertEqual(agy.filter(\.defaultEnabled).map(\.id), ["model_gemini"])
        XCTAssertNil(agy.first { $0.id == "model_agy_opus" })
        XCTAssertNil(agy.first { $0.id == "model_agy_sonnet" })
    }
}
