import XCTest
@testable import AllnighterCore

/// `HandoverGate` runs the house gate shape (`TryFixGate`/`SliceGate`): danger blocks, doubt
/// does not (PM_Relay.md §5 item 1). Each danger class has one realistic imperative-handover
/// block test; benign handovers — including ones that MENTION a danger only to prohibit or
/// undo it — must pass.
final class HandoverGateTests: XCTestCase {

    // MARK: - Each danger class blocks on a realistic imperative handover

    func testCredentialsSecretsBlocks() {
        let handover = """
        Next round: wire up the CI pipeline. Also, please commit the API key directly \
        into the repo config so the build server can read it at boot time.
        """
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, let code, _, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .credentialsSecrets)
        XCTAssertEqual(code, "RELAY_HANDOVER_UNSAFE")
        XCTAssertTrue(snippet.lowercased().contains("commit"), "snippet: \(snippet)")
    }

    func testSigningDistributionBlocks() {
        let handover = """
        The build looks good locally. Go ahead and run codesign on the release binary, \
        then submit it to the App Store for review.
        """
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, _, _, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .signingDistribution)
        XCTAssertTrue(snippet.lowercased().contains("codesign"), "snippet: \(snippet)")
    }

    func testDestructiveGitBlocks() {
        let handover = """
        The last three commits on main are broken beyond repair. Please run \
        git reset --hard on main to clear them before you start the new work.
        """
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, _, _, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .destructiveGit)
        XCTAssertTrue(snippet.lowercased().contains("reset"), "snippet: \(snippet)")
    }

    func testSandboxPermissionsBlocks() {
        let handover = """
        The unsigned test build won't launch on your machine. Run \
        `sudo spctl --master-disable` first so Gatekeeper stops blocking it.
        """
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, _, _, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .sandboxPermissions)
        XCTAssertTrue(snippet.lowercased().contains("spctl"), "snippet: \(snippet)")
    }

    func testMassDeletionBlocks() {
        let handover = """
        The src tree has drifted too far from the design. Just run `rm -rf src/` \
        to start the module over from scratch, then rebuild it slice by slice.
        """
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, _, _, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .massDeletion)
        XCTAssertTrue(snippet.lowercased().contains("rm -rf"), "snippet: \(snippet)")
    }

    // MARK: - Benign handovers pass, including prohibitive mentions of danger

    func testRmRfOfBuildDirIsAllowed() {
        let handover = """
        Getting weird stale-module errors. Run `rm -rf node_modules && npm install` \
        to get a clean install before you continue.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    func testNeverCommitApiKeyDoesNotBlock() {
        let handover = """
        Wire the new worker up to the staging API. Never commit the API key — keep it \
        in the keychain entry we already use for staging and read it at runtime.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    func testDontForcePushDoesNotBlock() {
        let handover = """
        You'll need to rebase feat/onboarding onto main this round. Don't force-push \
        when you're done — open a PR instead so I can review the diff before it lands.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    func testRevertingAnAccidentalHardResetDoesNotBlock() {
        let handover = """
        Yesterday's session ended badly: revert the accidental git reset --hard from \
        last night and restore the three lost commits from the reflog before you \
        start anything new.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    func testMentioningAppStoreWithNoImperativeDoesNotBlock() {
        let handover = """
        Status check only this round: the app is already live on the App Store, no \
        signing changes needed. Focus on the settings screen redesign instead.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    /// A realistic multi-slice PM handover in the Ikiro-style territory PM_Relay.md §0
    /// describes: batches several slices, points at screenshot artifacts, names tests to
    /// run, and mentions deploying to TestFlight — none of which are danger classes.
    /// "Deploy" alone must not block.
    func testRealisticMultiSliceHandoverPasses() {
        let handover = """
        Good round. Both items I flagged last time are done exactly as described — I \
        checked the actual commits, not just your report.

        For this round, build the next three slices together and let me review after \
        (not gated slice-by-slice — the surface is low-risk):

        1. Wire the onboarding screen's "Skip" button to the existing SkipOnboarding \
           service call.
        2. Add the empty-state illustration to the inbox when there are zero threads.
        3. Fix the settings toggle animation glitch reported in ISSUE-142.

        Take screenshots at artifacts/s88-onboarding/skip-flow.png and \
        artifacts/s88-onboarding/empty-inbox.png so I can review them against the \
        design-system exemplars next round.

        Run `swift test --filter OnboardingTests` before you commit, and once that's \
        green go ahead and commit with your usual message convention. If the TestFlight \
        build is still current we can deploy it after this batch lands so I can look at \
        it on-device — no rush on that part.
        """
        XCTAssertEqual(HandoverGate.evaluate(handoverText: handover), .allowed)
    }

    // MARK: - Blocked decision shape

    func testBlockedDecisionCarriesClassAndSnippet() {
        let handover = "Please commit the API key to the repo so CI can read it."
        let decision = HandoverGate.evaluate(handoverText: handover)
        guard case .blocked(let dangerClass, let code, let reason, let snippet) = decision else {
            return XCTFail("expected block, got \(decision)")
        }
        XCTAssertEqual(dangerClass, .credentialsSecrets)
        XCTAssertEqual(code, "RELAY_HANDOVER_UNSAFE")
        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(snippet.isEmpty)
    }

    func testAllowedHandoverHasNoDanger() {
        XCTAssertTrue(HandoverGate.evaluate(handoverText: "Please add unit tests for the new parser.").isAllowed)
    }
}
