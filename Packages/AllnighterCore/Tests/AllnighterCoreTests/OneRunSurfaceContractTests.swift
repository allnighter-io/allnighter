import XCTest
@testable import AllnighterCore

/// ORS-S00a — red-first contract gates for One Run Surface.
///
/// Canonical grammar + deletion manifest. These assertions must fail until
/// production cutover lands (`docs/phases/One_Run_Surface.md` §ORS-S00).
/// Do not XCTSkip / XCTExpectFailure / weaken them to go green.
final class OneRunSurfaceContractTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    // MARK: - Helpers

    private func command(_ name: String) -> ContractRegistry.CommandSpec? {
        reg.commands.first { $0.name == name }
    }

    private func flagNames(of command: ContractRegistry.CommandSpec) -> Set<String> {
        Set(command.flags.map(\.name))
    }

    private func teamRunAuditProperties() throws -> Set<String> {
        let schema = ContractSchema.teamRunSchema()
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any], "TeamRunJSON schema missing $defs")
        let audit = try XCTUnwrap(defs["Audit"] as? [String: Any], "TeamRunJSON schema missing Audit $def")
        let props = try XCTUnwrap(audit["properties"] as? [String: Any], "Audit schema missing properties")
        return Set(props.keys)
    }

    // MARK: - A. Canonical single-run read grammar

    func testShowCommandIsRegisteredWithRunIdArg() {
        let show = command("show")
        XCTAssertNotNil(show, "ORS cutover: canonical single-run read command `show` must be registered")
        let args = show?.args ?? []
        let acceptsRunId = args.contains {
            $0.name.contains("run") || $0.name.contains("id") || $0.name.contains("latest")
        }
        XCTAssertTrue(
            acceptsRunId,
            "ORS cutover: `show` args must accept a run id (got \(args.map(\.name)))"
        )
    }

    func testShowDeclaresJsonAndStreamFlags() throws {
        let show = try XCTUnwrap(command("show"), "ORS cutover: canonical single-run read command `show` must be registered")
        let flags = flagNames(of: show)
        XCTAssertTrue(flags.contains("json"), "ORS cutover: `show` must declare `--json`")
        XCTAssertTrue(
            flags.contains("stream"),
            "ORS cutover: `show` must declare `--stream` (canonical reattach surface)"
        )
    }

    func testShowFullAndStreamAreMutuallyExclusive() throws {
        let show = try XCTUnwrap(command("show"), "ORS cutover: canonical single-run read command `show` must be registered")
        let groups = show.mutuallyExclusiveFlags
        let exclusive = groups.contains { group in
            Set(group).isSuperset(of: ["full", "stream"])
        }
        XCTAssertTrue(
            exclusive,
            "ORS cutover: `--full` and `--stream` must be mutually exclusive on `show` (got \(groups))"
        )
    }

    /// QDR-S01 (Qwen driver bug report): `--answer` is the documented retrieval
    /// path for work already in the record of an in-flight, killed, or failed
    /// run. It is an output mode, so it excludes every other output mode.
    func testShowDeclaresAnswerFlagExclusiveWithOtherModes() throws {
        let show = try XCTUnwrap(command("show"), "QDR-S01: `show` must declare the answer retrieval flag")
        let flags = flagNames(of: show)
        XCTAssertTrue(flags.contains("answer"), "QDR-S01: `show` must declare `--answer`")
        let groups = show.mutuallyExclusiveFlags
        for peer in ["json", "full", "stream"] {
            XCTAssertTrue(
                groups.contains { Set($0).isSuperset(of: ["answer", peer]) },
                "QDR-S01: `--answer` and `--\(peer)` must be mutually exclusive on `show` (got \(groups))"
            )
        }
    }

    /// QDR-S01: the exclusions are enforced at the registry gate (exit-2 shape),
    /// and `--answer` alone clears it.
    func testShowAnswerModePairsRejectedAtTheGate() {
        for peer in ["json", "full", "stream"] {
            let err = CLIUsage.validateFlagConstraints(
                args: ["run_x", "--answer", "--\(peer)"],
                commandName: "show", registry: reg
            )
            XCTAssertNotNil(err, "--answer + --\(peer) should be rejected")
            XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
        }
        XCTAssertNil(CLIUsage.validateFlagConstraints(
            args: ["run_x", "--answer"], commandName: "show", registry: reg
        ))
    }

    func testShowEffectsAreNonSpendingNonWriting() throws {
        let show = try XCTUnwrap(command("show"), "ORS cutover: canonical single-run read command `show` must be registered")
        let effects = show.effects
        XCTAssertEqual(
            effects.quotaSpend, .never,
            "ORS cutover: `show` must never spend quota (read surface)"
        )
        XCTAssertEqual(
            effects.repoWrite, .never,
            "ORS cutover: `show` must never write the repo (read surface)"
        )
        XCTAssertEqual(
            effects.workerStart, .never,
            "ORS cutover: `show` must never start a worker (read surface)"
        )
        XCTAssertEqual(
            effects.destructive, .never,
            "ORS cutover: `show` must never be destructive (read surface)"
        )
    }

    // MARK: - B. Retired single-run read grammar absent

    func testTeamStatusCommandIsAbsent() {
        XCTAssertNil(
            command("team status"),
            "ORS cutover: retired `team status` must be deleted from ContractRegistry (no alias/shim)"
        )
    }

    func testTeamResultCommandIsAbsent() {
        XCTAssertNil(
            command("team result"),
            "ORS cutover: retired `team result` must be deleted from ContractRegistry (no alias/shim)"
        )
    }

    func testNoWatchFollowTailAttachOrActivityCommands() {
        // Single-run read synonyms of `show --stream` are banned (ORS hard cutover).
        // Exact names only — multi-word pilot surfaces (e.g. `pair pilot watch`) are out of scope.
        let banned: Set<String> = ["watch", "follow", "tail", "attach", "activity"]
        let names = Set(reg.commands.map(\.name))
        for bannedName in banned {
            XCTAssertFalse(
                names.contains(bannedName),
                "ORS cutover: no public command named or aliased `\(bannedName)` (use `show --stream` only)"
            )
        }
        // Examples must not teach those as top-level `alln <verb>` single-run surfaces.
        for example in reg.examples {
            let cmd = example.command.trimmingCharacters(in: .whitespaces)
            for bannedName in banned {
                let asVerb = "alln \(bannedName)"
                XCTAssertFalse(
                    cmd == asVerb || cmd.hasPrefix(asVerb + " "),
                    "ORS cutover: example `\(example.id)` must not teach retired single-run verb `\(bannedName)` (command: \(cmd))"
                )
            }
        }
    }

    func testPsDeclaresNoWaitForChangeFlag() throws {
        let ps = try XCTUnwrap(command("ps"), "ORS cutover: `ps` must exist as fleet inventory")
        let flags = flagNames(of: ps)
        XCTAssertFalse(
            flags.contains("wait-for-change"),
            "ORS cutover: `ps` must not gain `--wait-for-change` (fleet view stays non-waiting)"
        )
    }

    // MARK: - C. No parallel public status schema

    func testStatusWaitTimeoutErrorCodeIsAbsent() {
        let codes = Set(reg.errors.map(\.code))
        XCTAssertFalse(
            codes.contains("STATUS_WAIT_TIMEOUT"),
            "ORS cutover: delete STATUS_WAIT_TIMEOUT with the team-status waiter (no parallel status schema)"
        )
    }

    func testResultNotReadyErrorCodeIsAbsent() {
        let codes = Set(reg.errors.map(\.code))
        XCTAssertFalse(
            codes.contains("RESULT_NOT_READY"),
            "ORS cutover: delete RESULT_NOT_READY with team result (no parallel result-not-ready schema)"
        )
    }

    // MARK: - D. No public filesystem escape hatch

    func testTeamRunJSONSchemaHasNoRunJournalPath() throws {
        let auditProps = try teamRunAuditProperties()
        XCTAssertFalse(
            auditProps.contains("runJournalPath"),
            "ORS cutover: public TeamRunJSON Audit must not publish runJournalPath (filesystem escape hatch)"
        )
        // Required-list must not force the hatch either.
        let schema = ContractSchema.teamRunSchema()
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let audit = try XCTUnwrap(defs["Audit"] as? [String: Any])
        let required = (audit["required"] as? [String]) ?? []
        XCTAssertFalse(
            required.contains("runJournalPath"),
            "ORS cutover: Audit.required must not include runJournalPath"
        )

        // Encoded payload must not emit the key at any nesting level — a stray
        // nested producer must not survive even if the Swift type looks clean.
        let run = try Fixtures.run(.runComplete)
        let trj = TeamRunJSONMapper.map(
            run, models: try Fixtures.models(), manifests: [], context: .init()
        )
        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data))
        XCTAssertFalse(
            Self.jsonContainsKey(root, "runJournalPath"),
            "ORS cutover: encoded TeamRunJSON must not contain runJournalPath anywhere"
        )
    }

    /// Depth-first key scan over a JSONSerialization tree.
    private static func jsonContainsKey(_ value: Any, _ key: String) -> Bool {
        if let dict = value as? [String: Any] {
            if dict.keys.contains(key) { return true }
            return dict.values.contains { jsonContainsKey($0, key) }
        }
        if let arr = value as? [Any] {
            return arr.contains { jsonContainsKey($0, key) }
        }
        return false
    }

    // MARK: - E. Detached acknowledgement points at the one surface

    func testRunAcknowledgementNextActionIsShowStream() {
        // Core-owned next-action factory for the pull-delivery wait path.
        // Target shape: `alln show <id> --stream` (One_Run_Surface detached ack).
        let command = AsyncTeamNextAction.waitForTerminal(runId: "run_123").command
        XCTAssertTrue(
            command.contains("alln show "),
            "ORS cutover: detached ack nextAction must point at `alln show <id>` (got: \(command))"
        )
        XCTAssertTrue(
            command.contains(" --stream"),
            "ORS cutover: detached ack nextAction must include `--stream` (got: \(command))"
        )
        XCTAssertFalse(
            command.contains("team status"),
            "ORS cutover: detached ack must not teach retired `team status` waiter (got: \(command))"
        )
        XCTAssertFalse(
            command.contains("--wait-for"),
            "ORS cutover: detached ack must not teach `--wait-for` pull waiter (got: \(command))"
        )
    }
}
