import XCTest

/// Base class for tests that touch durable support state — lanes, flocks, run
/// storage, relays, ownership receipts.
///
/// **Why this exists.** `ExecutionLaneRegistry` (and its `RunWriteLockRegistry`
/// alias), `RunStore`, `ProcessOwnership` and the relay coordinators all persist
/// under `AllnighterPaths.support`. Unless a test redirects that root, they write
/// into the user's REAL `~/Library/Application Support/Allnighter/`.
///
/// That is not theoretical. A test run interrupted mid-flight left a live
/// `xctest` process holding the real `v1:test` lane; `isIdentityAlive` then
/// correctly refused to reap a live holder, so the lane stayed held and every
/// LATER run's first `acquire()` returned nil — poisoning the suite on that
/// machine until the directory was deleted by hand. Runs of the same commit
/// returned 0 failures, a hang, and 6 failures depending only on leftover state.
///
/// `AllnighterPaths.support` honours `ALLNIGHTER_SUPPORT_DIR`, so redirecting it
/// per-test is enough. Several classes already did this inline
/// (`ExecutionLaneTests`, `RunServiceTests`, …); this is the same pattern, shared.
///
/// **Deliberately NOT solved in `AllnighterPaths`.** Making the production path
/// fall back to a temp dir when it detects a test would re-introduce exactly what
/// CODE_RED deleted: a silent parallel empty product instead of an honest
/// failure. See the comment on `AllnighterPaths.support`. Isolation belongs in
/// the tests, not in the shipping path.
///
/// **Subclass contract — read this before overriding.** XCTest does NOT chain
/// these for you. A subclass that overrides `setUpWithError()`/
/// `tearDownWithError()` **must** call super, or this base is silently bypassed
/// and the test writes to real user data while still passing green:
///
/// ```swift
/// override func setUpWithError() throws {
///     try super.setUpWithError()   // FIRST — establishes the hermetic root
///     …
/// }
///
/// override func tearDownWithError() throws {
///     …
///     try super.tearDownWithError()  // LAST — restores + removes the root
/// }
/// ```
///
/// Overriding the non-throwing `setUp()`/`tearDown()` instead needs no super
/// call: XCTest invokes `setUpWithError()` before `setUp()`, and `tearDown()`
/// before `tearDownWithError()`.
class HermeticSupportTestCase: XCTestCase {
    /// The per-test support root. Non-nil for the duration of a test.
    private(set) var hermeticSupportDir: URL!

    /// Whatever `ALLNIGHTER_SUPPORT_DIR` was before this test, so a nested or
    /// already-isolating caller is restored exactly rather than unset.
    private var previousSupportDir: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousSupportDir = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"]
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-hermetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        hermeticSupportDir = support
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
    }

    override func tearDownWithError() throws {
        if let previousSupportDir {
            setenv("ALLNIGHTER_SUPPORT_DIR", previousSupportDir, 1)
        } else {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
        }
        previousSupportDir = nil
        if let hermeticSupportDir {
            try? FileManager.default.removeItem(at: hermeticSupportDir)
        }
        hermeticSupportDir = nil
        try super.tearDownWithError()
    }
}
