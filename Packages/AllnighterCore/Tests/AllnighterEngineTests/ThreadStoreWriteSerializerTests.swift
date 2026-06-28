import XCTest
@testable import AllnighterEngine

final class ThreadStoreWriteSerializerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadStoreWriteSerializerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testSynchronizedRunsBodyAndReturnsValue() throws {
        let value = try ThreadStoreWriteSerializer.synchronized(rootDirectory: root) {
            42
        }
        XCTAssertEqual(value, 42)
    }

    func testSynchronizedPropagatesThrows() {
        XCTAssertThrowsError(
            try ThreadStoreWriteSerializer.synchronized(rootDirectory: root) {
                throw TestError.boom
            }
        ) { error in
            XCTAssertEqual(error as? TestError, .boom)
        }
    }

    func testNestedSynchronizedSameRootThrowsWhenTesting() throws {
        try ThreadStoreWriteSerializer.synchronizedForTesting(rootDirectory: root) {
            XCTAssertThrowsError(
                try ThreadStoreWriteSerializer.synchronizedForTesting(rootDirectory: root) {
                    XCTFail("nested synchronized should not run")
                }
            ) { error in
                XCTAssertEqual(
                    error as? ThreadStoreWriteSerializer.WriteSerializerError,
                    .reentrantSynchronized
                )
            }
        }
    }

    func testDifferentRootsDoNotCrossDetectReentrancy() throws {
        let other = root.appendingPathComponent("nested-root", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        let nested = try ThreadStoreWriteSerializer.synchronizedForTesting(rootDirectory: root) {
            try ThreadStoreWriteSerializer.synchronizedForTesting(rootDirectory: other) {
                "ok"
            }
        }
        XCTAssertEqual(nested, "ok")
    }

    private enum TestError: Error, Equatable {
        case boom
    }
}
