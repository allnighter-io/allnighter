import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class VendorSubstitutionRuntimeTests: XCTestCase {
    func testParkedVendorWaitIsQuiescentWithoutWorkerReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendor-substitution-\(UUID().uuidString)", isDirectory: true)
        let runDir = root.appendingPathComponent("run_test", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let run = TeamRun(
            id: "test",
            prompt: "p",
            status: .queued,
            phase: .waitingForVendor,
            createdAt: Date(),
            blocker: RunBlocker(resource: .vendorBackoff, quotaScope: "claude_code")
        )
        XCTAssertTrue(
            VendorSubstitutionRuntime.isOriginalWorkerQuiescent(
                runDirectory: runDir,
                run: run
            )
        )
    }
}
