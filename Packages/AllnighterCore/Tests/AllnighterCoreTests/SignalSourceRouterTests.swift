import XCTest
@testable import AllnighterCore

/// The X route is a SAFETY rule, not a preference: running a media downloader
/// (`vvx` → yt-dlp) against X risks the user's own X account under X's terms.
/// These tests exist so that rule cannot regress into prompt prose.
final class SignalSourceRouterTests: XCTestCase {

    func testEveryKnownXHostFormIsModelOnly() {
        for url in [
            "https://x.com/heynavtoor/status/2080238307813040398?s=51",
            "https://www.x.com/aiwithmayank/status/2080228272911389138",
            "https://mobile.twitter.com/someone/status/123",
            "https://twitter.com/someone/status/123",
            "http://m.x.com/someone/status/123",
            "https://t.co/abc123",
            "x.com/someone/status/123"            // scheme-less paste
        ] {
            XCTAssertEqual(SignalSourceRouter.route(forURL: url), .xModelOnly, url)
        }
    }

    /// The dangerous case the prompt alone could not prevent: an X post that
    /// CONTAINS a video still must never reach the downloader.
    func testXVideoPostIsStillModelOnly() {
        let url = "https://x.com/someone/status/123/video/1"
        XCTAssertEqual(SignalSourceRouter.route(forURL: url), .xModelOnly)
        XCTAssertFalse(SignalSourceRouter.allowsVideoTool(forPrompt: "what does this mean for us? \(url)"))
    }

    func testNonXLinksRouteToTheVideoTool() {
        for url in [
            "https://www.youtube.com/watch?v=abc",
            "https://youtu.be/abc",
            "https://vimeo.com/12345",
            "https://example.com/blog/release-notes"
        ] {
            XCTAssertEqual(SignalSourceRouter.route(forURL: url), .videoTool, url)
        }
    }

    func testNoURLMeansPastedText() {
        XCTAssertEqual(SignalSourceRouter.route(forPrompt: "here is a post I copied out by hand"), .pastedText)
        XCTAssertFalse(SignalSourceRouter.allowsVideoTool(forPrompt: "no link here"))
    }

    /// Fail-safe: a prompt mixing an X link with a YouTube link must NOT authorise
    /// the downloader, in either order — otherwise the scout could aim it at the X one.
    func testAnyXLinkAnywhereForcesTheXRoute() {
        let x = "https://x.com/someone/status/123"
        let yt = "https://youtu.be/abc"
        XCTAssertEqual(SignalSourceRouter.route(forPrompt: "compare \(x) and \(yt)"), .xModelOnly)
        XCTAssertEqual(SignalSourceRouter.route(forPrompt: "compare \(yt) and \(x)"), .xModelOnly)
        XCTAssertFalse(SignalSourceRouter.allowsVideoTool(forPrompt: "compare \(yt) and \(x)"))
    }

    /// The scout's teaching is GENERATED from these rules, so the prompt cannot
    /// authorise something the policy forbids.
    func testScoutInstructionsCarryTheProhibitionAndTheInstallHint() {
        let text = SignalSourceRouter.scoutInstructions
        XCTAssertTrue(text.contains("NEVER run vvx"), text)
        // The invocation must be the real one — `vvx <url>` alone is an argument
        // parser error, and an unquoted url gets glob-mangled by the shell.
        XCTAssertTrue(text.contains("vvx sense \"<url>\""), text)
        XCTAssertTrue(text.contains(SignalSourceRouter.videoToolInstallHint), text)
        XCTAssertTrue(text.contains("X account"), text)
    }

    func testTheScoutSkillActuallyEmbedsTheGeneratedRules() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("signal_source_reader"))
        XCTAssertTrue(skill.template.contains("NEVER run vvx"), skill.template)
        XCTAssertTrue(skill.template.contains(SignalSourceRouter.videoToolInstallHint))
    }
}
