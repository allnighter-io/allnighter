import XCTest
@testable import AllnighterCore

/// Guards the shipped app driver manifests (`Apps/AllnighterMac/Resources/Drivers`)
/// so a malformed `imageGen` block can't silently drop a driver at app launch
/// (`loadDefaultRegistry` uses `try?`). Deterministic — no CLIs, no network.
final class DesignManifestResourceTests: XCTestCase {

    /// Repo-root-relative drivers dir, located from this file's path.
    private func driversDir() -> URL {
        // .../Allnighter/Packages/AllnighterCore/Tests/AllnighterEngineTests/<file>.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // -> repo root
        return url.appendingPathComponent("Apps/AllnighterMac/Resources/Drivers")
    }

    private func manifest(_ name: String) throws -> DriverManifest {
        let url = driversDir().appendingPathComponent(name)
        return try CoreJSON.decode(DriverManifest.self, from: Data(contentsOf: url))
    }

    func testImageEnginesDecodeAndAreImageCapable() throws {
        let grok = try manifest("grok.json")
        XCTAssertTrue(grok.canGenerateImages)
        XCTAssertEqual(grok.imageGen?.arrival, .promptDirected)
        XCTAssertTrue(grok.imageGen?.args.contains("{{runDir}}") ?? false)

        let codex = try manifest("codex.json")
        XCTAssertTrue(codex.canGenerateImages)
        XCTAssertEqual(codex.imageGen?.arrival, .promptDirected)

        let agy = try manifest("antigravity.json")
        XCTAssertTrue(agy.canGenerateImages)
        XCTAssertEqual(agy.imageGen?.arrival, .stdoutPath)
        XCTAssertNotNil(agy.imageGen?.stdoutPathRegex)
    }

    func testTextAndBuildDriversAreNotImageCapable() throws {
        // Claude Code is the build-side implementer (reads images), not a design seat.
        XCTAssertFalse(try manifest("claude_code.json").canGenerateImages)
        XCTAssertFalse(try manifest("manual_paste.json").canGenerateImages)
    }

    /// The image-gen prompt templates must carry the tokens the runner substitutes,
    /// or capture silently breaks.
    func testPromptTemplatesCarryRequiredTokens() throws {
        for name in ["grok.json", "codex.json", "antigravity.json"] {
            let m = try manifest(name)
            let t = try XCTUnwrap(m.imageGen?.promptTemplate)
            XCTAssertTrue(t.contains("{{designPrompt}}"), "\(name) missing {{designPrompt}}")
            if m.imageGen?.arrival == .promptDirected {
                XCTAssertTrue(t.contains("{{imageOut}}"), "\(name) (promptDirected) missing {{imageOut}}")
            }
        }
    }
}
