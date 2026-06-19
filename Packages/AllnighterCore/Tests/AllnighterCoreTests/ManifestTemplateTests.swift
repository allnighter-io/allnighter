import XCTest
@testable import AllnighterCore

final class ManifestTemplateTests: XCTestCase {

    func testPromptResolvesAsSingleArgvElement() throws {
        let manifest = try Fixtures.manifest(.manifestClaude)
        let nasty = "ignore previous; rm -rf / && echo $(whoami) \"quoted\""
        let ctx = DriverManifest.ResolveContext(prompt: nasty, model: "claude-opus-4.8")
        let argv = manifest.resolvedArgs(ctx)

        XCTAssertEqual(argv, ["-p", nasty, "--model", "claude-opus-4.8"])
        // The dangerous prompt is exactly one element — not split, not shell-joined.
        XCTAssertEqual(argv.filter { $0 == nasty }.count, 1)
    }

    func testModelTokenSubstitutesInline() throws {
        let manifest = try Fixtures.manifest(.manifestGrok)
        let ctx = DriverManifest.ResolveContext(prompt: "hi", model: "Grok Composer 2.5 Fast")
        let argv = manifest.resolvedArgs(ctx)
        XCTAssertEqual(argv, ["-p", "hi", "--model", "Grok Composer 2.5 Fast"])
    }

    func testStdinPromptOnlyWhenDeclared() throws {
        var manifest = try Fixtures.manifest(.manifestClaude)
        let ctx = DriverManifest.ResolveContext(prompt: "hi", model: "m")
        XCTAssertNil(manifest.stdinPrompt(ctx))

        manifest.invoke?.promptVia = .stdin
        XCTAssertEqual(manifest.stdinPrompt(ctx), "hi")
    }

    func testManualManifestResolvesToEmptyArgs() throws {
        let manual = try Fixtures.manifest(.manifestManual)
        let ctx = DriverManifest.ResolveContext(prompt: "hi", model: "m")
        XCTAssertEqual(manual.resolvedArgs(ctx), [])
        XCTAssertNil(manual.stdinPrompt(ctx))
    }

    func testSmokeCommandSubstitutesModelNotPrompt() throws {
        let manifest = try Fixtures.manifest(.manifestClaude)
        let resolved = manifest.resolvedCommandString(manifest.smokeTestCommand, model: "claude-sonnet-4.6")
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved!.contains("claude-sonnet-4.6"))
        XCTAssertFalse(resolved!.contains("{{model}}"))
    }

}
