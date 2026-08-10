import XCTest
@testable import AllnighterEngine

final class ServeDesiredStateTests: XCTestCase {

    private var tempRoot: URL!
    private var fm: FileManager!
    private let fixedDate = Date(timeIntervalSince1970: 1_000_000)
    private var fixedClock: () -> Date { { self.fixedDate } }

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fm = FileManager.default
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            // Restore writable permissions if needed
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempRoot.appendingPathComponent("Library/Application Support/Allnighter").path)
            try? fm.removeItem(at: tempRoot)
        }
    }

    private var homeURL: URL {
        tempRoot
    }

    private var storeURL: URL {
        ServeDesiredState.storeURL(homeDirectory: homeURL)
    }

    // MARK: - Absent

    func testAbsentFileReadsAbsent() {
        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        switch reading {
        case .absent:
            break
        default:
            XCTFail("expected .absent, got \(reading)")
        }
    }

    func testAbsentFileHasEnabledEffectiveState() {
        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        XCTAssertEqual(reading.effectiveState, .enabled)
    }

    // MARK: - Write + Read

    func testWriteDisabledReadsBackDisabled() {
        let result = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: fixedClock)
        XCTAssertNotNil(try? result.get())

        let reading = ServeDesiredState.read(homeDirectory: homeURL, clock: fixedClock)
        switch reading {
        case .present(let state, let updatedAt):
            XCTAssertEqual(state, .disabled)
            XCTAssertEqual(updatedAt, fixedDate)
        default:
            XCTFail("expected .present(.disabled), got \(reading)")
        }
    }

    func testWriteEnabledReadsBackEnabled() {
        let result = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: fixedClock)
        XCTAssertNotNil(try? result.get())

        let reading = ServeDesiredState.read(homeDirectory: homeURL, clock: fixedClock)
        switch reading {
        case .present(let state, let updatedAt):
            XCTAssertEqual(state, .enabled)
            XCTAssertEqual(updatedAt, fixedDate)
        default:
            XCTFail("expected .present(.enabled), got \(reading)")
        }
    }

    func testExplicitEnabledIsDistinguishableFromAbsent() {
        let result = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: fixedClock)
        XCTAssertNotNil(try? result.get())

        let reading = ServeDesiredState.read(homeDirectory: homeURL, clock: fixedClock)
        switch reading {
        case .absent:
            XCTFail("should not be absent after explicit write")
        case .present(let state, _):
            XCTAssertEqual(state, .enabled)
        case .unreadable:
            XCTFail("should not be unreadable")
        }
    }

    // MARK: - Disabled persists (simulated update)

    func testDisabledStatePersistsAfterSimulatedUpdate() {
        _ = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: fixedClock)

        let reading = ServeDesiredState.read(homeDirectory: homeURL, clock: fixedClock)
        switch reading {
        case .present(let state, _):
            XCTAssertEqual(state, .disabled)
        default:
            XCTFail("expected .present(.disabled)")
        }
    }

    // MARK: - Corrupt / truncated / future schema

    func testCorruptJSONReadsUnreadable() {
        let parent = storeURL.deletingLastPathComponent()
        try! fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try! Data("not json".utf8).write(to: storeURL)

        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        switch reading {
        case .unreadable(let reason):
            XCTAssertTrue(reason.contains("corrupt") || reason.contains("truncated"))
        default:
            XCTFail("expected .unreadable, got \(reading)")
        }
    }

    func testTruncatedJSONReadsUnreadable() {
        let parent = storeURL.deletingLastPathComponent()
        try! fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try! Data("{\"schemaVersion\"".utf8).write(to: storeURL)

        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        switch reading {
        case .unreadable(let reason):
            XCTAssertTrue(reason.contains("corrupt") || reason.contains("truncated"))
        default:
            XCTFail("expected .unreadable, got \(reading)")
        }
    }

    func testHigherSchemaVersionReadsUnreadable() {
        let parent = storeURL.deletingLastPathComponent()
        try! fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let futureJSON = """
        {"schemaVersion":99,"state":"disabled","updatedAt":"2001-09-09T01:46:40Z"}
        """
        try! Data(futureJSON.utf8).write(to: storeURL)

        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        switch reading {
        case .unreadable(let reason):
            XCTAssertTrue(reason.contains("future schema version"))
        default:
            XCTFail("expected .unreadable, got \(reading)")
        }
    }

    func testUnreadableEffectiveStateIsEnabled() {
        let parent = storeURL.deletingLastPathComponent()
        try! fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try! Data("garbage".utf8).write(to: storeURL)

        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        XCTAssertEqual(reading.effectiveState, .enabled)
    }

    func testReadingNeverRewritesCorruptFile() {
        let parent = storeURL.deletingLastPathComponent()
        try! fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let corruptBytes = Data("!!!corrupt!!!".utf8)
        try! corruptBytes.write(to: storeURL)

        _ = ServeDesiredState.read(homeDirectory: homeURL)
        let onDisk = try! Data(contentsOf: storeURL)
        XCTAssertEqual(onDisk, corruptBytes, "read must never overwrite corrupt data")
    }

    // MARK: - Atomic write

    func testWriteFailurePreservesPriorState() throws {
        _ = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: fixedClock)

        let parent = storeURL.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: parent.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }

        let failResult = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: fixedClock)
        switch failResult {
        case .success:
            XCTFail("write should fail on read-only directory")
        case .failure(let f):
            XCTAssertEqual(f.code, "SERVE_DESIRED_STATE_WRITE_FAILED")
        }

        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)

        let reading = ServeDesiredState.read(homeDirectory: homeURL, clock: fixedClock)
        switch reading {
        case .present(let state, let updatedAt):
            XCTAssertEqual(state, .disabled, "prior state must be preserved after failed write")
            XCTAssertEqual(updatedAt, fixedDate)
        default:
            XCTFail("prior state should still be present")
        }
    }

    // MARK: - Clock control

    func testClockControlsUpdatedAt() {
        let date1 = Date(timeIntervalSince1970: 1_000_000)
        let date2 = Date(timeIntervalSince1970: 2_000_000)

        _ = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: { date1 })
        let reading1 = ServeDesiredState.read(homeDirectory: homeURL)

        _ = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: { date2 })
        let reading2 = ServeDesiredState.read(homeDirectory: homeURL)

        switch reading1 {
        case .present(_, let updatedAt):
            XCTAssertEqual(updatedAt, date1)
        default:
            XCTFail("expected present")
        }

        switch reading2 {
        case .present(_, let updatedAt):
            XCTAssertEqual(updatedAt, date2)
        default:
            XCTFail("expected present")
        }
    }

    // MARK: - storeURL

    func testStoreURLUsesApplicationSupport() {
        let url = ServeDesiredState.storeURL(homeDirectory: homeURL)
        XCTAssertTrue(url.path.contains("Library/Application Support/Allnighter"))
        XCTAssertTrue(url.path.hasSuffix("serve-desired-state.json"))
    }

    // MARK: - Failure

    func testFailureEquatable() {
        let a = ServeDesiredState.Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED", message: "msg")
        let b = ServeDesiredState.Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED", message: "msg")
        XCTAssertEqual(a, b)
    }

    // MARK: - Write creates parent directory

    func testWriteCreatesParentDirectories() {
        let parent = storeURL.deletingLastPathComponent()
        XCTAssertFalse(fm.fileExists(atPath: parent.path))

        _ = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: fixedClock)
        XCTAssertTrue(fm.fileExists(atPath: parent.path), "parent directory should be created")
        XCTAssertTrue(fm.fileExists(atPath: storeURL.path), "file should be created")
    }

    // MARK: - Write overwrite

    // MARK: - Atomic write proof

    final class RemoveRecordingFileManager: FileManager {
        private(set) var removedURLs: [URL] = []

        override func removeItem(at url: URL) throws {
            removedURLs.append(url)
            try super.removeItem(at: url)
        }

        override func removeItem(atPath path: String) throws {
            removedURLs.append(URL(fileURLWithPath: path))
            try super.removeItem(atPath: path)
        }
    }

    func testAtomicOverwriteNeverRemovesDestination() {
        let recorder = RemoveRecordingFileManager()
        let destURL = storeURL

        _ = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: fixedClock)

        _ = ServeDesiredState.write(.enabled, homeDirectory: homeURL, fileManager: recorder, clock: fixedClock)

        let destRemovals = recorder.removedURLs.filter { $0.path == destURL.path }
        XCTAssertEqual(
            destRemovals.count,
            0,
            "destination must never be removed during overwrite — removal creates a window where .absent maps to .enabled, defeating explicit .disabled"
        )
    }

    func testOverwriteUpdatesState() {
        _ = ServeDesiredState.write(.enabled, homeDirectory: homeURL, clock: fixedClock)
        _ = ServeDesiredState.write(.disabled, homeDirectory: homeURL, clock: fixedClock)

        let reading = ServeDesiredState.read(homeDirectory: homeURL)
        switch reading {
        case .present(let state, _):
            XCTAssertEqual(state, .disabled)
        default:
            XCTFail("expected present")
        }
    }

    // MARK: - Sendable conformance

    func testStateIsSendable() {
        let state: ServeDesiredState.State = .enabled
        let reading: ServeDesiredState.Reading = .present(state: state, updatedAt: fixedDate)
        let _: @Sendable () -> ServeDesiredState.Reading = { reading }
    }

    func testFailureIsSendable() {
        let f = ServeDesiredState.Failure(code: "X", message: "Y")
        let _: @Sendable () -> ServeDesiredState.Failure = { f }
    }
}
