import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// SH-S01 — one `ResolvedRunInvocation` serves preview and run (Laws 3–4).
final class ResolvedRunInvocationTests: XCTestCase {

    private func sonnet() -> Model {
        Model(id: "model_sonnet", displayName: "Sonnet 5", modelLabel: "sonnet",
              driverId: "claude_code", role: .both)
    }

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
              driverId: "claude_code", role: .both)
    }

    private func fable() -> Model {
        Model(id: "model_fable", displayName: "Fable", modelLabel: "fable",
              driverId: "claude_code", role: .both)
    }

    private func settings(defaultModel: String = "model_sonnet") -> DefaultModelSettings {
        DefaultModelSettings(
            defaultTier: .flagship,
            allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: [defaultModel], balanced: [defaultModel], fast: [defaultModel])
        )
    }

    private func context(
        models: [Model]? = nil,
        writeLockHeld: Bool? = nil
    ) -> RunInvocationResolveContext {
        let bench = models ?? [sonnet(), opus(), fable()]
        return RunInvocationResolveContext(
            models: bench,
            teams: TeamCatalog.all,
            readyModels: bench,
            readyModelIds: Set(bench.map(\.id)),
            defaultSettings: settings(),
            writeLockHeld: writeLockHeld
        )
    }

    private func resolve(
        message: String = "probe",
        projectId: String = "proj_test",
        root: String = "/tmp/alln-sh-s01",
        mode: RunInvocationFlagMode = .dryRun,
        flags: RunInvocationNormalizedFlags,
        writeLockHeld: Bool? = nil
    ) -> ResolvedRunInvocation {
        var flags = flags
        if flags.projectId == nil { flags.projectId = projectId }
        return RunInvocationResolver.resolve(
            RunInvocationInput(message: message, projectRoot: root, flagMode: mode, flags: flags),
            context: context(writeLockHeld: writeLockHeld)
        )
    }

    /// Substitute `{name}` tokens, then assert argv identity.
    private func substitutedArgv(_ invocation: ResolvedRunInvocation) -> [String] {
        invocation.argvTemplate.map { token in
            if token.hasPrefix("{"), token.hasSuffix("}"), token.count > 2 {
                let name = String(token.dropFirst().dropLast())
                return invocation.templateVariables[name] ?? token
            }
            return token
        }
    }

    private func assertNoDroppedSelectors(
        _ invocation: ResolvedRunInvocation,
        team: String? = nil,
        worker: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let argv = invocation.argvTemplate
        if let team {
            XCTAssertTrue(argv.contains("--team"), "dropped --team", file: file, line: line)
            XCTAssertTrue(argv.contains(team), "dropped team id \(team)", file: file, line: line)
        }
        if let worker {
            XCTAssertTrue(argv.contains("--worker"), "dropped --worker", file: file, line: line)
            XCTAssertTrue(argv.contains(worker), "dropped worker id \(worker)", file: file, line: line)
        }
        XCTAssertEqual(invocation.templateVariables["message"], "probe", file: file, line: line)
        XCTAssertTrue(argv.contains("{message}"), file: file, line: line)
    }

    // MARK: - Table matrix

    func testDefaultRouteResolvesAutoSingleSeat() {
        let dry = resolve(flags: .init(json: true))
        let fg = resolve(mode: .foreground, flags: .init(json: true))

        XCTAssertEqual(dry.teamPresetId, "default_chat")
        XCTAssertEqual(dry.seatCount, 1, "execution Default Team is one seat, not lead+crew roster")
        XCTAssertEqual(dry.workerId, "model_sonnet")
        XCTAssertTrue(dry.autoResolved)
        XCTAssertFalse(dry.explicitWorkerChosen)
        XCTAssertTrue(dry.mutating)
        XCTAssertEqual(dry.flagMode, .dryRun)

        // Preview/execution identity
        XCTAssertEqual(dry.teamPresetId, fg.teamPresetId)
        XCTAssertEqual(dry.workerId, fg.workerId)
        XCTAssertEqual(dry.seatCount, fg.seatCount)
        XCTAssertEqual(dry.writePolicy, fg.writePolicy)
        XCTAssertEqual(dry.seats.map(\.modelId), fg.seats.map(\.modelId))

        let dryRunJSON = dry.makeDryRunJSON()
        XCTAssertEqual(dryRunJSON.counts.seatCount, 1)
        XCTAssertEqual(dryRunJSON.workerId, "model_sonnet")
        XCTAssertTrue(dryRunJSON.nextAction.command.contains("{message}"))
        XCTAssertFalse(dryRunJSON.nextAction.command.contains("<message>"))
    }

    func testExplicitWorkerDoesNotProjectDefaultTeamRoster() {
        let dry = resolve(flags: .init(workerId: "model_sonnet", json: true))
        let fg = resolve(mode: .foreground, flags: .init(workerId: "model_sonnet", json: true))

        XCTAssertEqual(dry.workerId, "model_sonnet")
        XCTAssertTrue(dry.explicitWorkerChosen)
        XCTAssertFalse(dry.autoResolved)
        XCTAssertEqual(dry.seatCount, 1)
        XCTAssertEqual(dry.seats.map(\.modelId), ["model_sonnet"])
        // Warnings must not carry multi-seat Default Team roster noise.
        XCTAssertFalse(dry.warnings.contains(where: { $0.localizedCaseInsensitiveContains("self-fusion") }))

        let json = dry.makeDryRunJSON()
        XCTAssertEqual(json.counts.seatCount, 1)
        XCTAssertEqual(json.workerId, "model_sonnet")
        XCTAssertTrue(json.nextAction.command.contains("--worker"))
        XCTAssertTrue(json.nextAction.command.contains("model_sonnet"))

        assertNoDroppedSelectors(dry, worker: "model_sonnet")
        XCTAssertEqual(dry.teamPresetId, fg.teamPresetId)
        XCTAssertEqual(dry.workerId, fg.workerId)
        XCTAssertEqual(dry.seatCount, fg.seatCount)
        XCTAssertTrue(substitutedArgv(dry).contains("model_sonnet"))
    }

    func testExplicitTeamUsesThatTeamSeats() {
        let dry = resolve(flags: .init(teamId: "code_bug_hunt", json: true))
        let fg = resolve(mode: .foreground, flags: .init(teamId: "code_bug_hunt", json: true))

        XCTAssertEqual(dry.teamPresetId, "code_bug_hunt")
        XCTAssertTrue(dry.explicitTeamChosen)
        XCTAssertFalse(dry.mutating, "Bug Hunt is an answer team")
        XCTAssertGreaterThan(dry.seatCount, 1, "answer team projects crew seats")
        XCTAssertEqual(dry.seatCount, fg.seatCount)
        XCTAssertEqual(dry.teamPresetId, fg.teamPresetId)
        assertNoDroppedSelectors(dry, team: "code_bug_hunt")

        let json = dry.makeDryRunJSON()
        XCTAssertEqual(json.teamPresetId, "code_bug_hunt")
        XCTAssertTrue(json.nextAction.command.contains("--team"))
        XCTAssertTrue(json.nextAction.command.contains("code_bug_hunt"))
    }

    func testTeamPlusWorkerPinsSingleSeat() {
        let dry = resolve(flags: .init(teamId: "code_bug_hunt", workerId: "model_sonnet", json: true))
        let fg = resolve(
            mode: .foreground,
            flags: .init(teamId: "code_bug_hunt", workerId: "model_sonnet", json: true)
        )

        XCTAssertEqual(dry.seatCount, 1)
        XCTAssertEqual(dry.workerId, "model_sonnet")
        XCTAssertEqual(dry.teamPresetId, "code_bug_hunt")
        XCTAssertEqual(dry.seatCount, fg.seatCount)
        XCTAssertEqual(dry.workerId, fg.workerId)
        assertNoDroppedSelectors(dry, team: "code_bug_hunt", worker: "model_sonnet")
    }

    func testDetachSharesResolvedSelectorsWithForeground() {
        let fg = resolve(mode: .foreground, flags: .init(workerId: "model_sonnet", json: true))
        let detach = resolve(mode: .detach, flags: .init(workerId: "model_sonnet", json: true))

        XCTAssertEqual(fg.teamPresetId, detach.teamPresetId)
        XCTAssertEqual(fg.workerId, detach.workerId)
        XCTAssertEqual(fg.seatCount, detach.seatCount)
        XCTAssertEqual(fg.writePolicy, detach.writePolicy)
        XCTAssertTrue(detach.argvTemplate.contains("--detach"))
        XCTAssertFalse(fg.argvTemplate.contains("--detach"))
        assertNoDroppedSelectors(detach, worker: "model_sonnet")
    }

    func testValueFlagsSurviveInArgvTemplate() {
        // Mode-scoped flags (executor / thread ids) are exercised in dedicated
        // mode tests below — dry-run must not accept them without companions.
        let dry = resolve(
            flags: .init(
                workerId: "model_sonnet",
                effort: .high,
                lane: .code,
                type: nil,
                context: "secret context prose",
                json: true,
                commitMessage: "secret commit",
                proofCommand: "swift test",
                idleTimeoutSeconds: 600,
                handshakeTimeoutSeconds: 60,
                firstActivityTimeoutSeconds: 30,
                wallTimeoutSeconds: 3600,
                idempotencyKey: "idem-1",
                retryOf: "run_prior",
                agent: "agent_x"
            )
        )

        let argv = dry.argvTemplate
        XCTAssertTrue(argv.contains("--effort") && argv.contains("high"))
        XCTAssertTrue(argv.contains("--lane") && argv.contains("code"))
        XCTAssertTrue(argv.contains("--context") && argv.contains("{context}"))
        XCTAssertTrue(argv.contains("--idle-timeout") && argv.contains("600"))
        XCTAssertTrue(argv.contains("--handshake-timeout") && argv.contains("60"))
        XCTAssertTrue(argv.contains("--first-activity-timeout") && argv.contains("30"))
        XCTAssertTrue(argv.contains("--wall-timeout") && argv.contains("3600"))
        XCTAssertTrue(argv.contains("--idempotency-key") && argv.contains("idem-1"))
        XCTAssertTrue(argv.contains("--retry-of") && argv.contains("run_prior"))
        XCTAssertTrue(argv.contains("--commit-message") && argv.contains("{commitMessage}"))
        XCTAssertTrue(argv.contains("--proof") && argv.contains("{proof}"))
        XCTAssertTrue(argv.contains("--agent") && argv.contains("agent_x"))

        XCTAssertEqual(dry.templateVariables["context"], "secret context prose")
        XCTAssertEqual(dry.templateVariables["commitMessage"], "secret commit")
        XCTAssertEqual(dry.templateVariables["proof"], "swift test")
        // Sensitive prose must not appear raw in the template tokens.
        XCTAssertFalse(argv.contains("secret context prose"))
        XCTAssertFalse(argv.contains("secret commit"))

        let substituted = substitutedArgv(dry)
        XCTAssertTrue(substituted.contains("secret context prose"))
        XCTAssertTrue(substituted.contains("secret commit"))
        XCTAssertTrue(substituted.contains("swift test"))
        assertNoDroppedSelectors(dry, worker: "model_sonnet")
    }

    func testDetachOnlyFlagsSurviveInDetachMode() {
        let detach = resolve(
            mode: .detach,
            flags: .init(
                workerId: "model_sonnet",
                json: true,
                threadId: "thread_1",
                conversationId: "conv_1",
                messageId: "msg_1"
            )
        )
        XCTAssertTrue(detach.argvTemplate.contains("--detach"))
        XCTAssertTrue(detach.argvTemplate.contains("--thread-id") && detach.argvTemplate.contains("thread_1"))
        XCTAssertTrue(detach.argvTemplate.contains("--conversation-id") && detach.argvTemplate.contains("conv_1"))
        XCTAssertTrue(detach.argvTemplate.contains("--message-id") && detach.argvTemplate.contains("msg_1"))
        assertNoDroppedSelectors(detach, worker: "model_sonnet")
    }

    func testExecutorSurvivesInTryFixMode() {
        let tryFix = resolve(
            mode: .tryFix,
            flags: .init(
                workerId: "model_sonnet",
                json: true,
                executorTeamId: "build_slice"
            )
        )
        XCTAssertTrue(tryFix.argvTemplate.contains("--try-fix"))
        XCTAssertTrue(tryFix.argvTemplate.contains("--executor") && tryFix.argvTemplate.contains("build_slice"))
        assertNoDroppedSelectors(tryFix, worker: "model_sonnet")
    }

    func testAcceptSurvivorsSurvivesWithRetryOfAcrossModes() {
        for mode in [RunInvocationFlagMode.dryRun, .foreground, .detach, .tryFix] {
            let inv = resolve(
                mode: mode,
                flags: .init(
                    workerId: "model_sonnet",
                    json: true,
                    acceptSurvivors: true,
                    retryOf: "run_prior"
                )
            )
            XCTAssertTrue(inv.argvTemplate.contains("--accept-survivors"), "\(mode)")
            XCTAssertTrue(inv.argvTemplate.contains("--retry-of") && inv.argvTemplate.contains("run_prior"), "\(mode)")
        }
    }

    func testBooleanFlagsSurviveInArgvTemplate() {
        let dry = resolve(
            flags: .init(
                workerId: "model_sonnet",
                json: true,
                noCommit: true,
                acceptSurvivors: true,
                retryOf: "run_prior"
            )
        )
        XCTAssertTrue(dry.argvTemplate.contains("--no-commit"))
        XCTAssertTrue(dry.argvTemplate.contains("--accept-survivors"))
        XCTAssertTrue(dry.argvTemplate.contains("--json"))
        assertNoDroppedSelectors(dry, worker: "model_sonnet")
    }

    func testDryRunJSONProjectionKeepsSchemaV1Shape() throws {
        let dry = resolve(flags: .init(workerId: "model_sonnet", json: true))
        let json = dry.makeDryRunJSON()
        let data = try JSONEncoder().encode(json)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(obj?["mutating"])
        XCTAssertNil(obj?["argvTemplate"], "argvTemplate stays internal until v3 cut")
        XCTAssertNil(obj?["templateVariables"])
        XCTAssertNil(obj?["writePolicy"])
        XCTAssertNil(obj?["effects"])
    }

    func testMakeRunRequestPreservesSelectors() {
        let dry = resolve(flags: .init(teamId: "code_bug_hunt", workerId: "model_sonnet", effort: .high, json: true))
        let request = dry.makeRunRequest(message: "probe")
        XCTAssertEqual(request.presetId, "code_bug_hunt")
        XCTAssertEqual(request.workerId, "model_sonnet")
        XCTAssertEqual(request.effort, .high)
        XCTAssertEqual(request.message, "probe")

        let again = RunInvocationResolver.resolve(
            RunInvocationInput(request: request, flagMode: .foreground),
            context: context()
        )
        XCTAssertEqual(again.teamPresetId, dry.teamPresetId)
        XCTAssertEqual(again.workerId, dry.workerId)
        XCTAssertEqual(again.seatCount, dry.seatCount)
    }

    func testWriteLockProbeOnlyWhenMutating() {
        let mutating = resolve(
            flags: .init(workerId: "model_sonnet", json: true),
            writeLockHeld: true
        )
        XCTAssertEqual(mutating.writeLockHeld, true)
        XCTAssertTrue(mutating.warnings.contains(where: { $0.contains("write lock") }))

        let answer = resolve(
            flags: .init(teamId: "code_bug_hunt", json: true),
            writeLockHeld: true
        )
        XCTAssertNil(answer.writeLockHeld, "read-only teams do not probe the write lock")
    }
}
