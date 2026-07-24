import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ResidentCoordinatorInstallTests: XCTestCase {
    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [[String]] = []

        func append(_ arguments: [String]) {
            lock.lock(); defer { lock.unlock() }
            entries.append(arguments)
        }

        var all: [[String]] {
            lock.lock(); defer { lock.unlock() }
            return entries
        }
    }

    func testPlistContainsOnlyResidentServeInvocation() throws {
        let data = try ResidentCoordinatorInstall.plistData(
            binaryPath: "/opt/alln/alln", pathEnvironment: "/opt/agents:/usr/bin"
        )
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, ResidentCoordinatorInstall.label)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/opt/alln/alln", "serve"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
        XCTAssertEqual(
            (plist["EnvironmentVariables"] as? [String: String])?["PATH"],
            "/opt/agents:/usr/bin"
        )
    }

    func testInstallWritesPlistAndBootstrapsOnlyItsLabel() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("alln")
        try Data().write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let calls = CallLog()

        let result = ResidentCoordinatorInstall.install(
            argv0: binary.path,
            home: root,
            launchctl: { args in calls.append(args); return .success },
            currentHealth: { .init(
                state: .available,
                coordinatorId: "coord-test",
                pid: 123,
                contractVersion: ContractRegistry.contractVersion,
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                journal: .init(incrementalDurable: true, orphanRecovery: true, runsDirWritable: true),
                loopback: .init(listening: true)
            ) }
        )
        let installed = try XCTUnwrap(try? result.get())
        XCTAssertTrue(installed.enabled)
        XCTAssertEqual(installed.coordinatorId, "coord-test")
        XCTAssertEqual(installed.pid, 123)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.plistPath))
        XCTAssertEqual(calls.all.count, 2)
        XCTAssertEqual(calls.all.last?.first, "bootstrap")
        XCTAssertEqual(calls.all.last?.last, installed.plistPath)
    }

    func testStableRunningBinaryPreservesInstalledSymlinkForFutureRebuilds() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-stable-bin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("built-alln")
        let link = root.appendingPathComponent("alln")
        try Data().write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        XCTAssertEqual(
            ResidentCoordinatorInstall.stableRunningBinary(argv0: link.path, pathEnvironment: nil),
            link.path
        )
    }

    func testInstallRefusesToRestartActiveCoordinator() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-install-active-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("alln")
        try Data().write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let calls = CallLog()
        let restartStore = ResidentCoordinatorRestartStore(directory: root.appendingPathComponent("Coordinator"))

        let result = ResidentCoordinatorInstall.install(
            argv0: binary.path,
            home: root,
            launchctl: { args in calls.append(args); return .success },
            currentHealth: { .init(
                state: .available,
                coordinatorId: "coord-test",
                pid: 123,
                contractVersion: ContractRegistry.contractVersion,
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                journal: .init(incrementalDurable: true, orphanRecovery: true, runsDirWritable: true),
                loopback: .init(listening: true),
                activeObligationCount: 2
            ) },
            restartStore: restartStore
        )

        let draining = try XCTUnwrap(try? result.get())
        XCTAssertEqual(draining.action, "draining")
        XCTAssertEqual(calls.all.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ResidentCoordinatorInstall.plistURL(home: root).path))
        XCTAssertEqual(restartStore.load()?.binaryVersion, AllnighterVersionIdentity.binaryVersion)
    }

    func testInstallFailsWhenLaunchdDoesNotPublishCurrentIdentity() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-install-timeout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("alln")
        try Data().write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let result = ResidentCoordinatorInstall.install(
            argv0: binary.path,
            home: root,
            launchctl: { _ in .success },
            currentHealth: { .init(
                state: .foregroundOnly,
                contractVersion: ContractRegistry.contractVersion,
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                journal: .init(incrementalDurable: true, orphanRecovery: true, runsDirWritable: true),
                loopback: .init(listening: false)
            ) },
            activationAttempts: 1
        )

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ResidentCoordinatorInstall.InstallError, .activationTimeout)
        }
    }
}
