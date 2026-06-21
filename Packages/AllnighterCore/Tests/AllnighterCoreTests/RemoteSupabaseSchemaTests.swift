import XCTest
@testable import AllnighterCore

final class RemoteSupabaseSchemaTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AllnighterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // AllnighterCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    private var schemaSQL: String {
        get throws {
            try String(
                contentsOf: repoRoot.appendingPathComponent("supabase/migrations/20260621020800_remote_schema.sql"),
                encoding: .utf8
            )
        }
    }

    private var realtimeSQL: String {
        get throws {
            try String(
                contentsOf: repoRoot.appendingPathComponent("supabase/migrations/20260621020955_enable_relay_realtime_publication.sql"),
                encoding: .utf8
            )
        }
    }

    private let relayTables = [
        "mac_agents",
        "trusted_devices",
        "pair_requests",
        "command_inbox",
        "command_acks",
        "event_envelopes",
        "media_refs",
        "media_keys",
    ]

    func testRelayTablesHaveRLS() throws {
        let sql = try schemaSQL
        for table in relayTables {
            XCTAssertTrue(sql.contains("CREATE TABLE IF NOT EXISTS \"public\".\"\(table)\""), "missing table \(table)")
            XCTAssertTrue(sql.contains("ALTER TABLE \"public\".\"\(table)\" ENABLE ROW LEVEL SECURITY;"), "missing RLS for \(table)")
        }
    }

    func testCommandKindCheckTracksCoreEnum() throws {
        let sql = try schemaSQL
        let expectedKinds = Set(RemoteCommandKind.allCases.map(\.rawValue))
        let line = try XCTUnwrap(
            sql.components(separatedBy: .newlines)
                .first { $0.contains("command_inbox_kind_check") }
        )
        let quotedKinds = Set(
            line.components(separatedBy: "'")
                .enumerated()
                .compactMap { index, value in index.isMultiple(of: 2) ? nil : value }
        )
        XCTAssertEqual(quotedKinds, expectedKinds)
        XCTAssertFalse(line.lowercased().contains("shell"))
    }

    func testStartRunRowsMustCarrySealedPayloadShape() throws {
        let sql = try schemaSQL
        let line = try XCTUnwrap(
            sql.components(separatedBy: .newlines)
                .first { $0.contains("command_inbox_start_run_sealed_payload_check") }
        )
        XCTAssertTrue(line.contains("\"kind\" <> 'startRun'"))
        XCTAssertTrue(line.contains("\"payload\" ->> 'kind'"))
        XCTAssertTrue(line.contains("'sealedBlob'"))
        XCTAssertTrue(line.contains("\"payload\" ? 'sealedBlob'"))
        XCTAssertTrue(line.contains("NOT (\"payload\" ? 'lightPayload'"))
    }

    func testThreeTierRLSPoliciesArePinnedToDeviceAndMacClaims() throws {
        let sql = try schemaSQL
        for helper in [
            "\"public\".\"remote_device_id\"()",
            "\"public\".\"remote_mac_agent_id\"()",
            "\"public\".\"approved_remote_device\"",
            "\"public\".\"mac_agent_claim_matches\"",
        ] {
            XCTAssertTrue(sql.contains(helper), "missing helper \(helper)")
        }

        XCTAssertTrue(sql.contains("CREATE POLICY \"approved devices insert command inbox\""))
        XCTAssertTrue(sql.contains("(\"from_device_id\" = \"public\".\"remote_device_id\"())"))
        XCTAssertTrue(sql.contains("\"public\".\"approved_remote_device\"(\"mac_agent_id\", \"from_device_id\")"))

        XCTAssertTrue(sql.contains("CREATE POLICY \"mac agents select command inbox\""))
        XCTAssertTrue(sql.contains("\"public\".\"mac_agent_claim_matches\"(\"account_id\", \"mac_agent_id\")"))

        XCTAssertTrue(sql.contains("CREATE POLICY \"approved devices select event envelopes\""))
        XCTAssertTrue(sql.contains("\"public\".\"approved_remote_device\"(\"mac_agent_id\", \"public\".\"remote_device_id\"())"))

        XCTAssertTrue(sql.contains("CREATE POLICY \"users insert own pair requests\""))
        XCTAssertTrue(sql.contains("CREATE POLICY \"mac agents insert trusted devices\""))
    }

    func testMediaKeysAllowMacAgentUpsertForResealOnlyToActiveDevices() throws {
        let sql = try schemaSQL
        let insertPolicy = try policyBlock(named: "mac agents insert media keys", sql: sql)
        let updatePolicy = try policyBlock(named: "mac agents update media keys", sql: sql)

        for policy in [insertPolicy, updatePolicy] {
            XCTAssertTrue(policy.contains("ON \"public\".\"media_keys\""))
            XCTAssertTrue(policy.contains("\"public\".\"mac_agent_claim_matches\"(\"m\".\"account_id\", \"r\".\"mac_agent_id\")"))
            XCTAssertTrue(policy.contains("\"d\".\"device_id\" = \"media_keys\".\"device_id\""))
            XCTAssertTrue(policy.contains("\"d\".\"mac_agent_id\" = \"r\".\"mac_agent_id\""))
            XCTAssertTrue(policy.contains("\"d\".\"revoked\" = false"))
            XCTAssertTrue(policy.contains("\"d\".\"valid_until\" >= \"now\"()"))
        }
        XCTAssertTrue(updatePolicy.contains("FOR UPDATE"))
        XCTAssertTrue(updatePolicy.contains("WITH CHECK"))
    }

    func testMediaRefsAllowMacAgentUpsertForBlobRefresh() throws {
        let sql = try schemaSQL
        let insertPolicy = try policyBlock(named: "mac agents insert media refs", sql: sql)
        let updatePolicy = try policyBlock(named: "mac agents update media refs", sql: sql)

        for policy in [insertPolicy, updatePolicy] {
            XCTAssertTrue(policy.contains("ON \"public\".\"media_refs\""))
            XCTAssertTrue(policy.contains("\"m\".\"id\" = \"media_refs\".\"mac_agent_id\""))
            XCTAssertTrue(policy.contains("\"public\".\"mac_agent_claim_matches\"(\"m\".\"account_id\", \"media_refs\".\"mac_agent_id\")"))
        }
        XCTAssertTrue(updatePolicy.contains("FOR UPDATE"))
        XCTAssertTrue(updatePolicy.contains("WITH CHECK"))
    }

    func testCloudRelayTableColumnsStayContentLight() throws {
        let forbiddenNames: Set<String> = [
            "body",
            "content",
            "image",
            "images",
            "output",
            "outputs",
            "plan",
            "plans",
            "plaintext",
            "prompt",
            "raw",
        ]
        let sql = try schemaSQL
        for table in relayTables {
            let columns = try columnNames(in: table, sql: sql)
            XCTAssertTrue(columns.isDisjoint(with: forbiddenNames), "\(table) added plaintext-prone columns: \(columns.intersection(forbiddenNames))")
        }
    }

    func testRealtimePublicationContainsOnlyLiveRelayTables() throws {
        let sql = try realtimeSQL
        for table in ["command_inbox", "command_acks", "event_envelopes", "pair_requests"] {
            XCTAssertTrue(sql.contains("tablename = '\(table)'"), "missing realtime guard for \(table)")
            XCTAssertTrue(sql.contains("add table public.\(table)"), "missing realtime publication for \(table)")
        }
        for table in ["media_refs", "media_keys", "trusted_devices"] {
            XCTAssertFalse(sql.contains("add table public.\(table)"), "\(table) should not be broadcast through realtime")
        }
    }

    private func columnNames(in table: String, sql: String) throws -> Set<String> {
        let marker = "CREATE TABLE IF NOT EXISTS \"public\".\"\(table)\" ("
        guard let markerRange = sql.range(of: marker) else {
            XCTFail("missing table \(table)")
            return []
        }
        guard let closeRange = sql[markerRange.upperBound...].range(of: "\n);") else {
            XCTFail("missing table close for \(table)")
            return []
        }
        let block = sql[markerRange.upperBound..<closeRange.lowerBound]
        return Set(block.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\"") else { return nil }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            return parts.count > 1 ? String(parts[1]) : nil
        })
    }

    private func policyBlock(named name: String, sql: String) throws -> String {
        let marker = "CREATE POLICY \"\(name)\""
        guard let start = sql.range(of: marker)?.lowerBound else {
            XCTFail("missing policy \(name)")
            return ""
        }
        let rest = sql[start...]
        let afterMarker = rest.index(start, offsetBy: marker.count)
        let end = rest[afterMarker...].range(of: "\n\n\nCREATE POLICY")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }
}
