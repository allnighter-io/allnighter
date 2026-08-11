import XCTest
@testable import AllnighterCore

final class AllnighterSpawnEnvironmentPolicyTests: XCTestCase {

    func testServeTestInjectScrubbedFromSpawnEnvironment() {
        let env = AllnighterSpawnEnvironmentPolicy().environment(for: [
            "PATH": "/usr/bin",
            "ALLNIGHTER_SERVE_TEST_INJECT": "bootstrap-failure",
            "ALLNIGHTER_TOOL_TOKEN": "secret",
        ])
        XCTAssertNil(env["ALLNIGHTER_SERVE_TEST_INJECT"])
        XCTAssertNil(env["ALLNIGHTER_TOOL_TOKEN"])
    }

    func testChildProcessDoesNotInheritServeTestInject() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \"${ALLNIGHTER_SERVE_TEST_INJECT:-}\""]
        process.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment(
            base: [
                "PATH": "/usr/bin:/bin",
                "ALLNIGHTER_SERVE_TEST_INJECT": "bootstrap-failure",
            ]
        )

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(output, "", "scrubbed variable must not reach a spawned child")
    }
}
