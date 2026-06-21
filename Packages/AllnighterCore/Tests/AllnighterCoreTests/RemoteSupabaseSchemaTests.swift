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
        "snapshot_envelopes",
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
        XCTAssertTrue(line.contains("\"payload\" ? 'sealed_blob'"))
        XCTAssertTrue(line.contains("NOT (\"payload\" ? 'light_payload'"))
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
            XCTAssertTrue(policy.contains("\"public\".\"mac_agent_claim_matches\"(\"m\".\"account_id\", \"media_keys\".\"mac_agent_id\")"))
            XCTAssertTrue(policy.contains("\"r\".\"mac_agent_id\" = \"media_keys\".\"mac_agent_id\""))
            XCTAssertTrue(policy.contains("\"d\".\"device_id\" = \"media_keys\".\"device_id\""))
            XCTAssertTrue(policy.contains("\"d\".\"mac_agent_id\" = \"media_keys\".\"mac_agent_id\""))
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

    func testMediaKeysSelectPolicyReadsOnlyScopedRefAndDevice() throws {
        let sql = try schemaSQL
        let policy = try policyBlock(named: "approved devices select media keys", sql: sql)

        XCTAssertTrue(policy.contains("ON \"public\".\"media_keys\""))
        XCTAssertTrue(policy.contains("\"r\".\"mac_agent_id\" = \"media_keys\".\"mac_agent_id\""))
        XCTAssertTrue(policy.contains("\"r\".\"ref\" = \"media_keys\".\"ref\""))
        XCTAssertTrue(policy.contains("\"public\".\"mac_agent_claim_matches\"(\"m\".\"account_id\", \"media_keys\".\"mac_agent_id\")"))
        XCTAssertTrue(policy.contains("\"media_keys\".\"device_id\" = \"public\".\"remote_device_id\"()"))
        XCTAssertTrue(policy.contains("\"public\".\"approved_remote_device\"(\"media_keys\".\"mac_agent_id\", \"media_keys\".\"device_id\")"))
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
        for table in ["media_refs", "media_keys", "trusted_devices", "snapshot_envelopes"] {
            XCTAssertFalse(sql.contains("add table public.\(table)"), "\(table) should not be broadcast through realtime")
        }
    }

    func testScopedRelayUniquenessMatchesHeadlessContracts() throws {
        let sql = try schemaSQL
        XCTAssertTrue(try columnNames(in: "command_acks", sql: sql).contains("account_id"))
        XCTAssertTrue(try columnNames(in: "media_keys", sql: sql).contains("mac_agent_id"))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"command_inbox_pkey\" PRIMARY KEY (\"account_id\", \"mac_agent_id\", \"request_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"command_acks_pkey\" PRIMARY KEY (\"account_id\", \"mac_agent_id\", \"request_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"command_acks_inbox_scope_fkey\" FOREIGN KEY (\"account_id\", \"mac_agent_id\", \"request_id\") REFERENCES \"public\".\"command_inbox\"(\"account_id\", \"mac_agent_id\", \"request_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"event_envelopes_pkey\" PRIMARY KEY (\"account_id\", \"mac_agent_id\", \"id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"snapshot_envelopes_pkey\" PRIMARY KEY (\"account_id\", \"mac_agent_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"pair_requests_account_mac_device_key\" UNIQUE (\"account_id\", \"mac_agent_id\", \"device_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"trusted_devices_pkey\" PRIMARY KEY (\"account_id\", \"mac_agent_id\", \"device_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"trusted_devices_mac_device_key\" UNIQUE (\"mac_agent_id\", \"device_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"command_inbox_trusted_device_scope_fkey\" FOREIGN KEY (\"account_id\", \"mac_agent_id\", \"from_device_id\") REFERENCES \"public\".\"trusted_devices\"(\"account_id\", \"mac_agent_id\", \"device_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"media_refs_pkey\" PRIMARY KEY (\"mac_agent_id\", \"ref\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"media_keys_pkey\" PRIMARY KEY (\"mac_agent_id\", \"ref\", \"device_id\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"media_keys_ref_scope_fkey\" FOREIGN KEY (\"mac_agent_id\", \"ref\") REFERENCES \"public\".\"media_refs\"(\"mac_agent_id\", \"ref\")"
        ))
        XCTAssertTrue(sql.contains(
            "ADD CONSTRAINT \"media_keys_trusted_device_scope_fkey\" FOREIGN KEY (\"mac_agent_id\", \"device_id\") REFERENCES \"public\".\"trusted_devices\"(\"mac_agent_id\", \"device_id\")"
        ))
        XCTAssertFalse(sql.contains(
            "ADD CONSTRAINT \"trusted_devices_pkey\" PRIMARY KEY (\"device_id\")"
        ))
        XCTAssertFalse(sql.contains(
            "ADD CONSTRAINT \"media_refs_pkey\" PRIMARY KEY (\"ref\")"
        ))
        XCTAssertFalse(sql.contains(
            "ADD CONSTRAINT \"media_keys_pkey\" PRIMARY KEY (\"ref\", \"device_id\")"
        ))
    }

    func testRelayConstraintsReferenceDeclaredColumns() throws {
        let sql = try schemaSQL
        let tableColumns = try Dictionary(uniqueKeysWithValues: relayTables.map { table in
            (table, try columnNames(in: table, sql: sql))
        })
        var currentTable: String?

        for rawLine in sql.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let table = alteredPublicTable(in: line) {
                currentTable = table
                continue
            }
            guard line.contains("ADD CONSTRAINT"),
                  let sourceTable = currentTable,
                  let sourceColumns = tableColumns[sourceTable] else {
                continue
            }

            if line.contains(" PRIMARY KEY ") {
                try assert(columns: columns(after: "PRIMARY KEY", in: line), existIn: sourceColumns, table: sourceTable)
            }
            if line.contains(" UNIQUE ") {
                try assert(columns: columns(after: "UNIQUE", in: line), existIn: sourceColumns, table: sourceTable)
            }
            if line.contains(" FOREIGN KEY ") {
                try assert(columns: columns(after: "FOREIGN KEY", in: line), existIn: sourceColumns, table: sourceTable)
                if let target = try publicReferenceTarget(in: line),
                   let targetColumns = tableColumns[target.table] {
                    try assert(columns: target.columns, existIn: targetColumns, table: target.table)
                }
            }
        }
    }

    func testCommandAckPoliciesJoinInboxByFullScope() throws {
        let sql = try schemaSQL
        let insertPolicy = try policyBlock(named: "mac agents insert command acks", sql: sql)
        let selectPolicy = try policyBlock(named: "approved devices select command acks", sql: sql)

        for policy in [insertPolicy, selectPolicy] {
            XCTAssertTrue(policy.contains("\"c\".\"account_id\" = \"command_acks\".\"account_id\""))
            XCTAssertTrue(policy.contains("\"c\".\"mac_agent_id\" = \"command_acks\".\"mac_agent_id\""))
            XCTAssertTrue(policy.contains("\"c\".\"request_id\" = \"command_acks\".\"request_id\""))
        }
        XCTAssertTrue(insertPolicy.contains("\"public\".\"mac_agent_claim_matches\"(\"command_acks\".\"account_id\", \"command_acks\".\"mac_agent_id\")"))
        XCTAssertTrue(selectPolicy.contains("\"public\".\"mac_agent_claim_matches\"(\"command_acks\".\"account_id\", \"command_acks\".\"mac_agent_id\")"))
    }

    private func assert(
        columns: [String],
        existIn declaredColumns: Set<String>,
        table: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for column in columns {
            XCTAssertTrue(
                declaredColumns.contains(column),
                "\(table) constraint references missing column \(column)",
                file: file,
                line: line
            )
        }
    }

    private func alteredPublicTable(in line: String) -> String? {
        let marker = #"ALTER TABLE ONLY "public"."#
        guard line.hasPrefix(marker) else { return nil }
        let rest = line.dropFirst(marker.count)
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    private func columns(after marker: String, in line: String) throws -> [String] {
        guard let markerRange = line.range(of: marker),
              let open = line[markerRange.upperBound...].firstIndex(of: "("),
              let close = line[open...].firstIndex(of: ")") else {
            XCTFail("missing column list after \(marker): \(line)")
            return []
        }
        return line[line.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    private func publicReferenceTarget(in line: String) throws -> (table: String, columns: [String])? {
        let marker = #"REFERENCES "public"."#
        guard let markerRange = line.range(of: marker) else { return nil }
        let rest = line[markerRange.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else {
            XCTFail("missing public reference target: \(line)")
            return nil
        }
        let table = String(rest[..<close])
        let columns = try columns(after: "REFERENCES \"public\".\"\(table)\"", in: line)
        return (table, columns)
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
