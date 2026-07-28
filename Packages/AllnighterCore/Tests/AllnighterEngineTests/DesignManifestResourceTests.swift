import XCTest
@testable import AllnighterCore
import AgentOSCLI

/// Guards bundled AgentOS driver manifests so a malformed `imageGen` block can't
/// silently drop a driver at launch. Deterministic — no CLIs, no network.
final class DesignManifestResourceTests: XCTestCase {

    private func manifest(_ driverId: String) throws -> DriverManifest {
        let catalog = try CatalogLoader.bundled()
        return try XCTUnwrap(catalog.manifest(driverId: driverId), "missing driver \(driverId)")
    }

    func testImageEnginesDecodeAndAreImageCapable() throws {
        let grok = try manifest("grok")
        XCTAssertTrue(grok.canGenerateImages)
        XCTAssertEqual(grok.imageGen?.arrival, .promptDirected)
        XCTAssertTrue(grok.imageGen?.args.contains("{{runDir}}") ?? false)

        let codex = try manifest("codex")
        XCTAssertTrue(codex.canGenerateImages)
        XCTAssertEqual(codex.imageGen?.arrival, .promptDirected)

        let agy = try manifest("antigravity")
        XCTAssertTrue(agy.canGenerateImages)
        XCTAssertEqual(agy.imageGen?.arrival, .stdoutPath)
        XCTAssertNotNil(agy.imageGen?.stdoutPathRegex)
    }

    func testTextAndBuildDriversAreNotImageCapable() throws {
        let claude = try manifest("claude_code")
        XCTAssertFalse(claude.canGenerateImages)
        XCTAssertTrue(claude.canReadImages)
        XCTAssertTrue(try manifest("codex").canReadImages)
        XCTAssertFalse(try manifest("manual_paste").canGenerateImages)
    }

    func testPromptTemplatesCarryRequiredTokens() throws {
        for driverId in ["grok", "codex", "antigravity"] {
            let m = try manifest(driverId)
            let t = try XCTUnwrap(m.imageGen?.promptTemplate)
            XCTAssertTrue(t.contains("{{designPrompt}}"), "\(driverId) missing {{designPrompt}}")
            if m.imageGen?.arrival == .promptDirected {
                XCTAssertTrue(t.contains("{{imageOut}}"), "\(driverId) (promptDirected) missing {{imageOut}}")
            }
        }
    }
}
