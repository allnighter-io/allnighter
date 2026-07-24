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
            launchctl: { args in calls.append(args); return .success }
        )
        let installed = try XCTUnwrap(try? result.get())
        XCTAssertTrue(installed.enabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.plistPath))
        XCTAssertEqual(calls.all.count, 2)
        XCTAssertEqual(calls.all.last?.first, "bootstrap")
        XCTAssertEqual(calls.all.last?.last, installed.plistPath)
    }
}
