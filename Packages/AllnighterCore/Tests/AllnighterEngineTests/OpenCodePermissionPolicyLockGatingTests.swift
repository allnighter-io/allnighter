import XCTest
import AgentOSCLI
@testable import AllnighterEngine

/// CT-08 — mutating Allnighter runs must not auto-approve AgentOS sibling
/// `external_directory` without holding AgentOS's write lock.
final class OpenCodePermissionPolicyLockGatingTests: XCTestCase {
    func testMutatingAllnighterRunDoesNotAutoApproveAgentOSSiblingWithoutLock() {
        let home = "/Users/mike"
        let allnighter = "\(home)/Documents/GitHub/Allnighter"
        let agentOS = "\(home)/Documents/GitHub/AgentOS"
        let roots = OpenCodePermissionPolicy.defaultExternalDirectoryAllowRoots(home: home)

        // What RunService publishes for a mutating Allnighter seat.
        let held = OpenCodeHeldWriteLockRoots.forInvoke(repoRoot: allnighter, mutating: true)
        XCTAssertEqual(held, [allnighter])

        XCTAssertFalse(
            OpenCodePermissionPolicy.patternsAllowed(
                ["\(agentOS)/*"],
                allowRoots: roots,
                workingDirectory: allnighter,
                heldWriteLockRoots: held
            ),
            "sibling AgentOS must stay blocked without its write lock"
        )

        XCTAssertTrue(
            OpenCodePermissionPolicy.patternsAllowed(
                ["\(allnighter)/**"],
                allowRoots: roots,
                workingDirectory: allnighter,
                heldWriteLockRoots: held
            ),
            "run root remains allowed"
        )

        XCTAssertTrue(
            OpenCodePermissionPolicy.patternsAllowed(
                ["\(agentOS)/*"],
                allowRoots: roots,
                workingDirectory: allnighter,
                heldWriteLockRoots: held.union([agentOS])
            ),
            "sibling allowed only when that root's lock is held"
        )

        XCTAssertTrue(
            OpenCodeHeldWriteLockRoots.forInvoke(repoRoot: allnighter, mutating: false).isEmpty,
            "answer-only publishes no held roots"
        )
    }
}
