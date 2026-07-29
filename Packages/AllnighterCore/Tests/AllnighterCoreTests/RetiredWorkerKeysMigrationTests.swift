import XCTest
@testable import AllnighterCore

final class RetiredWorkerKeysMigrationTests: XCTestCase {
    func testTeamRunWorkerIdBecomesModelIdNotAgentId() throws {
        let (migrated, replacements) = RetiredWorkerKeysMigration.migrateJSONObject([
            "teamRun": ["workerId": "model_sonnet", "id": "run_1"]
        ], parentKey: nil)
        XCTAssertGreaterThan(replacements, 0)
        let root = try XCTUnwrap(migrated as? [String: Any])
        let teamRun = try XCTUnwrap(root["teamRun"] as? [String: Any])
        XCTAssertEqual(teamRun["modelId"] as? String, "model_sonnet")
        XCTAssertNil(teamRun["workerId"])
        XCTAssertNil(teamRun["agentId"])
    }

    func testWorkerAnswersRowsBecomeAgentId() throws {
        let (migrated, _) = RetiredWorkerKeysMigration.migrateJSONObject([
            "workerAnswers": [
                ["workerId": "model_sonnet#0", "modelId": "model_sonnet", "status": "done"]
            ]
        ], parentKey: nil)
        let root = try XCTUnwrap(migrated as? [String: Any])
        let answers = try XCTUnwrap(root["answers"] as? [[String: Any]])
        XCTAssertEqual(answers[0]["agentId"] as? String, "model_sonnet#0")
        XCTAssertNil(answers[0]["workerId"])
    }

    func testOnDiskMigrationIsIdempotentAndPathAware() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("wta_migration_test_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let runsDir = tempDir.appendingPathComponent("Runs/run_1", isDirectory: true)
        try fileManager.createDirectory(at: runsDir, withIntermediateDirectories: true)

        let journalFile = runsDir.appendingPathComponent("run.json")
        let oldJSON = """
        {
          "teamRun": { "workerId": "model_opus", "id": "run_1" },
          "devWorkerId": "model_opus",
          "pmWorkerId": "model_sonnet",
          "stages": [
            { "producedByWorkerId": "model_opus#0" }
          ],
          "workerAnswers": [
            { "workerId": "model_opus#0", "status": "done" }
          ],
          "answer": {
            "source": { "workerId": "model_opus#0", "modelId": "model_opus" }
          }
        }
        """
        try oldJSON.write(to: journalFile, atomically: true, encoding: .utf8)

        let migratedDir = tempDir.appendingPathComponent("Runs/run_2", isDirectory: true)
        try fileManager.createDirectory(at: migratedDir, withIntermediateDirectories: true)
        let migratedFile = migratedDir.appendingPathComponent("run.json")
        let alreadyMigratedJSON = """
        {
          "teamRun": { "modelId": "model_opus", "id": "run_2" },
          "devModelId": "model_opus",
          "pmModelId": "model_sonnet",
          "stages": [
            { "producedByAgentId": "model_opus#0" }
          ],
          "answers": [
            { "agentId": "model_opus#0", "status": "done" }
          ]
        }
        """
        try alreadyMigratedJSON.write(to: migratedFile, atomically: true, encoding: .utf8)

        let result1 = try RetiredWorkerKeysMigration.migrate(supportRoot: tempDir)
        XCTAssertEqual(result1.migratedFileCount, 1)
        XCTAssertGreaterThan(result1.totalReplacementsCount, 0)

        let updated = try String(contentsOf: journalFile, encoding: .utf8)
        let updatedObject = try JSONSerialization.jsonObject(with: Data(updated.utf8)) as? [String: Any]
        let teamRun = updatedObject?["teamRun"] as? [String: Any]
        XCTAssertEqual(teamRun?["modelId"] as? String, "model_opus")
        XCTAssertEqual(updatedObject?["devModelId"] as? String, "model_opus")
        XCTAssertEqual(updatedObject?["pmModelId"] as? String, "model_sonnet")
        let stages = updatedObject?["stages"] as? [[String: Any]]
        XCTAssertEqual(stages?.first?["producedByAgentId"] as? String, "model_opus#0")
        XCTAssertNotNil(updatedObject?["answers"])
        let answers = updatedObject?["answers"] as? [[String: Any]]
        XCTAssertEqual(answers?.first?["agentId"] as? String, "model_opus#0")
        let answerSource = (updatedObject?["answer"] as? [String: Any])?["source"] as? [String: Any]
        XCTAssertEqual(answerSource?["agentId"] as? String, "model_opus#0")
        XCTAssertFalse(updated.contains("devWorkerId"))
        XCTAssertFalse(updated.contains("pmWorkerId"))
        XCTAssertFalse(updated.contains("producedByWorkerId"))
        XCTAssertFalse(updated.contains("workerAnswers"))
        XCTAssertFalse(updated.contains("\"workerId\""))

        let alreadyMigrated = try String(contentsOf: migratedFile, encoding: .utf8)
        XCTAssertEqual(alreadyMigrated, alreadyMigratedJSON)

        let result2 = try RetiredWorkerKeysMigration.migrate(supportRoot: tempDir)
        XCTAssertEqual(result2.migratedFileCount, 0)
        XCTAssertEqual(result2.totalReplacementsCount, 0)

        let secondRun = try String(contentsOf: journalFile, encoding: .utf8)
        XCTAssertEqual(secondRun, updated)
    }
}
