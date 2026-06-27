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

    // MARK: - STR-S01: optional streaming block

    func testStreamingBlockRoundTrips() throws {
        let s = DriverManifest.Streaming(
            supported: true, mode: .jsonlStdout,
            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
            partialOutput: true, answerDeltaPaths: ["$.data"],
            finalAnswerSource: .parserAccumulator, stripAnsi: true, visibleReasoning: false)
        let m = DriverManifest(id: "x", displayName: "X", kind: .headlessCLI, streaming: s)
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(DriverManifest.self, from: data)
        XCTAssertEqual(back.streaming, s)
        XCTAssertTrue(back.canStream)
    }

    func testManifestWithoutStreamingDecodesToNil() throws {
        // A legacy manifest JSON (no `streaming` key) must still decode.
        let json = #"{"id":"legacy","manifestVersion":1,"displayName":"Legacy","kind":"headless_cli"}"#
        let m = try JSONDecoder().decode(DriverManifest.self, from: Data(json.utf8))
        XCTAssertNil(m.streaming)
        XCTAssertFalse(m.canStream)
    }

    func testCanStreamFalseWhenModeNoneOrUnsupported() {
        let unsupported = DriverManifest(id: "a", displayName: "A", kind: .headlessCLI,
                                         streaming: .init(supported: false, mode: .jsonlStdout))
        XCTAssertFalse(unsupported.canStream)
        let modeNone = DriverManifest(id: "b", displayName: "B", kind: .headlessCLI,
                                      streaming: .init(supported: true, mode: .none))
        XCTAssertFalse(modeNone.canStream)
    }

    func testResolvedStreamingArgsFallBackToInvokeArgs() throws {
        // No streaming.args → reuse invoke.args, resolved injection-safely.
        let manifest = try Fixtures.manifest(.manifestGrok)
        var m = manifest
        m.streaming = .init(supported: true, mode: .jsonlStdout, args: [])
        let ctx = DriverManifest.ResolveContext(prompt: "hi", model: "Grok")
        XCTAssertEqual(m.resolvedStreamingArgs(ctx), m.resolvedArgs(ctx))
    }

    func testResolvedStreamingArgsUseStreamingArgsWhenPresent() throws {
        let manifest = try Fixtures.manifest(.manifestGrok)
        var m = manifest
        m.streaming = .init(supported: true, mode: .jsonlStdout,
                            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"])
        let nasty = "a; rm -rf / \"x\""
        let ctx = DriverManifest.ResolveContext(prompt: nasty, model: "Grok")
        let argv = m.resolvedStreamingArgs(ctx)
        XCTAssertEqual(argv, ["-p", nasty, "--output-format", "streaming-json"])
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

    func testSmokeCommandSubstitutesWorkingDir() throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        let resolved = manifest.resolvedCommandString(
            #"agent --dir "{{workingDir}}" -m {{model}}"#, model: "composer-2.5",
            workingDir: "/tmp/alln-probe"
        )
        XCTAssertEqual(resolved, #"agent --dir "/tmp/alln-probe" -m composer-2.5"#)
    }

}
