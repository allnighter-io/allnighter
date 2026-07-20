import XCTest
@testable import AllnighterCore

/// AE-S11: widened surface hash + forced contractVersion bump.
final class ContractLockTests: XCTestCase {
    func testSurfaceHashChangesWhenFlagSummaryChanges() throws {
        var registry = ContractRegistry.milestone1
        let before = ContractRegistry.contractHash(registry)
        guard let idx = registry.commands.firstIndex(where: { $0.name == "version" }) else {
            return XCTFail("missing version command")
        }
        var cmd = registry.commands[idx]
        guard let flagIdx = cmd.flags.firstIndex(where: { $0.name == "json" }) else {
            return XCTFail("missing --json on version")
        }
        var flag = cmd.flags[flagIdx]
        flag.summary = flag.summary + " (ae-s11 probe)"
        cmd.flags[flagIdx] = flag
        registry.commands[idx] = cmd
        let after = ContractRegistry.contractHash(registry)
        XCTAssertNotEqual(before, after, "editing a FlagSpec summary must flip contractHash")
    }

    func testCheckFailsVersionNotBumpedWhenHashChangesWithoutBump() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ae-s11-lock-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(ContractExport.generatedDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Write a lock that matches current version but a stale hash.
        let stale = ContractRegistry.ContractLock(
            contractVersion: ContractRegistry.milestone1.contractVersion,
            contractHash: "0" + String(repeating: "a", count: 63)
        )
        let lockData = try CoreJSON.encode(stale) + Data("\n".utf8)
        try lockData.write(to: dir.appendingPathComponent(ContractExport.lockFilename))

        // Minimal other artifacts so check gets past missing-file logic after the version gate.
        // The version gate runs first and should return .versionNotBumped.
        let outcome = try ContractExport.check(from: root.path)
        guard case .versionNotBumped(let ver, let lockedHash, _) = outcome else {
            return XCTFail("expected versionNotBumped, got \(outcome)")
        }
        XCTAssertEqual(ver, ContractRegistry.milestone1.contractVersion)
        XCTAssertEqual(lockedHash, stale.contractHash)
    }

    func testLockArtifactMatchesCurrentRegistry() throws {
        let lockArt = try XCTUnwrap(
            try ContractExport.artifacts().first { $0.filename == ContractExport.lockFilename }
        )
        let lock = try CoreJSON.decode(
            ContractRegistry.ContractLock.self,
            from: Data(lockArt.contents.utf8)
        )
        XCTAssertEqual(lock.contractVersion, ContractRegistry.milestone1.contractVersion)
        XCTAssertEqual(lock.contractHash, ContractRegistry.contractHash())
    }
}
