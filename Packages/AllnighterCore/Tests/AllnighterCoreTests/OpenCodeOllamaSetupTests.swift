import XCTest
@testable import AllnighterCore

/// OCL-S02a — merge-only OpenCode ↔ local Ollama wiring. Fixtures only;
/// never the real `~/.config/opencode/opencode.json`, never a live Ollama.
final class OpenCodeOllamaSetupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    private let beforeJSON = """
        {
          "$schema": "https://opencode.ai/config.json",
          "enabled_providers": ["opencode-go", "openai"],
          "model": "opencode-go/kimi-k2.5",
          "permission": { "bash": "allow" },
          "provider": {
            "openai": {
              "options": { "apiKey": "sk-keep-me" }
            }
          }
        }
        """

    private let afterJSON = """
        {
          "$schema": "https://opencode.ai/config.json",
          "enabled_providers": ["opencode-go", "openai", "ollama"],
          "model": "opencode-go/kimi-k2.5",
          "permission": { "bash": "allow" },
          "provider": {
            "openai": {
              "options": { "apiKey": "sk-keep-me" }
            },
            "ollama": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "Ollama (local)",
              "options": {
                "baseURL": "http://localhost:11434/v1"
              }
            }
          }
        }
        """

    func testMergeKeepsOpencodeGoAndSiblingKeys() throws {
        var root = try OpenCodeOllamaProviderMerge.parseRoot(Data(beforeJSON.utf8))
        let result = try OpenCodeOllamaProviderMerge.merge(into: &root)
        XCTAssertTrue(result.addedProvider)
        XCTAssertTrue(result.addedEnabledProvider)
        XCTAssertFalse(result.filledBaseURL)
        try assertJSONEqual(root, afterJSON)

        let providers = try XCTUnwrap(root["enabled_providers"] as? [String])
        XCTAssertEqual(providers, ["opencode-go", "openai", "ollama"])
        let openai = try XCTUnwrap(
            (root["provider"] as? [String: Any])?["openai"] as? [String: Any]
        )
        let apiKey = try XCTUnwrap((openai["options"] as? [String: Any])?["apiKey"] as? String)
        XCTAssertEqual(apiKey, "sk-keep-me")
        XCTAssertEqual(root["model"] as? String, "opencode-go/kimi-k2.5")
    }

    func testMergeIsIdempotent() throws {
        var root = try OpenCodeOllamaProviderMerge.parseRoot(Data(afterJSON.utf8))
        let result = try OpenCodeOllamaProviderMerge.merge(into: &root)
        XCTAssertFalse(result.didChange)
        try assertJSONEqual(root, afterJSON)
    }

    func testMissingEnabledProvidersIsNotInventedAsOllamaOnlyAllowlist() throws {
        let json = """
            { "provider": { "openai": { "name": "keep" } }, "theme": "system" }
            """
        var root = try OpenCodeOllamaProviderMerge.parseRoot(Data(json.utf8))
        let result = try OpenCodeOllamaProviderMerge.merge(into: &root)
        XCTAssertTrue(result.addedProvider)
        XCTAssertFalse(result.addedEnabledProvider)
        XCTAssertNil(root["enabled_providers"])
        XCTAssertEqual(root["theme"] as? String, "system")
        let openai = try XCTUnwrap(
            (root["provider"] as? [String: Any])?["openai"] as? [String: Any]
        )
        XCTAssertEqual(openai["name"] as? String, "keep")
        XCTAssertNotNil((root["provider"] as? [String: Any])?["ollama"])
    }

    func testApplyBackupThenUndoRestoresBeforeObject() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        try Data(beforeJSON.utf8).write(to: config)

        let setup = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: now,
            dryRun: false
        )
        XCTAssertTrue(setup.wrote)
        XCTAssertTrue(setup.addedEnabledProvider)
        XCTAssertNotNil(setup.backupPath)
        try assertJSONEqual(
            try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: config)),
            afterJSON
        )
        let backup = try XCTUnwrap(setup.backupPath)
        try assertJSONEqual(
            try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: URL(fileURLWithPath: backup))),
            beforeJSON
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
        XCTAssertFalse(OpenCodeOllamaSetup.isRealDefaultConfig(config))

        let second = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: now.addingTimeInterval(60),
            dryRun: false
        )
        XCTAssertFalse(second.wrote)
        XCTAssertTrue(second.alreadyWired)

        let undone = try OpenCodeOllamaSetup.undo(
            configURL: config,
            receiptURL: receipt,
            now: now.addingTimeInterval(120)
        )
        XCTAssertTrue(undone.wrote)
        try assertJSONEqual(
            try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: config)),
            beforeJSON
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        let providers = try XCTUnwrap(
            try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: config))["enabled_providers"] as? [String]
        )
        XCTAssertEqual(providers, ["opencode-go", "openai"])
        XCTAssertFalse(providers.contains("ollama"))
    }

    func testDryRunDoesNotTouchFiles() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        try Data(beforeJSON.utf8).write(to: config)
        let before = try Data(contentsOf: config)

        let report = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: now,
            dryRun: true
        )
        XCTAssertFalse(report.wrote)
        XCTAssertEqual(try Data(contentsOf: config), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(leftovers.sorted(), ["opencode.json"])
    }

    func testInvalidJSONIsNotClobbered() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        let garbage = Data("{not-json".utf8)
        try garbage.write(to: config)

        XCTAssertThrowsError(
            try OpenCodeOllamaSetup.apply(
                configURL: config,
                receiptURL: receipt,
                now: now,
                dryRun: false
            )
        )
        XCTAssertEqual(try Data(contentsOf: config), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testTestHostRefusesRealDefaultConfig() {
        XCTAssertThrowsError(
            try OpenCodeOllamaSetup.resolveConfigURL(
                override: nil,
                isTestHost: true
            )
        ) { error in
            guard let typed = error as? OpenCodeOllamaSetup.Error,
                  case .testHostRefusedRealConfig = typed else {
                return XCTFail("expected testHostRefusedRealConfig, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try OpenCodeOllamaSetup.resolveConfigURL(
                override: OpenCodeOllamaSetup.defaultConfigURL,
                isTestHost: true
            )
        )
        let fixture = URL(fileURLWithPath: "/tmp/alln-ocl-s02a-fixture/opencode.json")
        XCTAssertEqual(
            try OpenCodeOllamaSetup.resolveConfigURL(override: fixture, isTestHost: true),
            fixture
        )
        XCTAssertTrue(AllnighterSupportRoot.isRunningUnderTestHost)
        XCTAssertFalse(
            OpenCodeOllamaSetup.isRealDefaultConfig(fixture)
        )
    }

    func testUndoWithoutReceiptFails() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("missing-receipt.json")
        try Data(beforeJSON.utf8).write(to: config)
        XCTAssertThrowsError(
            try OpenCodeOllamaSetup.undo(
                configURL: config,
                receiptURL: receipt,
                now: now
            )
        ) { error in
            guard let typed = error as? OpenCodeOllamaSetup.Error,
                  case .missingReceipt = typed else {
                return XCTFail("expected missingReceipt, got \(error)")
            }
        }
        try assertJSONEqual(
            try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: config)),
            beforeJSON
        )
    }

    func testCommandsAreRegistered() {
        let names = Set(ContractRegistry.milestone1.commands.map(\.name))
        XCTAssertTrue(names.contains("opencode-local setup"))
        XCTAssertTrue(names.contains("opencode-local undo"))
        XCTAssertTrue(names.contains("opencode-local status"))
    }

    // MARK: - Helpers

    private func scratchDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocl-s02a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func assertJSONEqual(_ root: [String: Any], _ expectedJSON: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try OpenCodeOllamaProviderMerge.parseRoot(Data(expectedJSON.utf8))
        let got = try canonical(root)
        let want = try canonical(expected)
        XCTAssertEqual(got, want, file: file, line: line)
    }

    private func canonical(_ obj: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
