import XCTest
@testable import AllnighterEngine

final class RunWriteLockTests: XCTestCase {
    func testNormalizeCollapsesTrailingSlash() {
        XCTAssertEqual(RunWriteLock.normalize("/tmp/repo/"), "/tmp/repo")
        XCTAssertEqual(RunWriteLock.normalize("/tmp/repo"), "/tmp/repo")
    }

    func testKeyIsStableForEquivalentPaths() {
        let a = RunWriteLock.key(repoRoot: "/tmp/repo")
        let b = RunWriteLock.key(repoRoot: "/tmp/repo/")
        XCTAssertEqual(a, b)
    }

    func testRegistryRefusesSecondAcquire() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:test"
        let first = await registry.acquire(key)
        let second = await registry.acquire(key)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        await registry.release(key)
        let third = await registry.acquire(key)
        XCTAssertTrue(third)
    }
}
