import XCTest
@testable import AllnighterCore

/// ORS-S00b — red-first hostile teaching gate + `show --stream` framing lock.
///
/// Every agent-taught command string must resolve to a live registered command,
/// and none may teach retired single-run read grammar. Stream framing is locked
/// from the registry/schema only (no process spawning).
///
/// These assertions must fail until production cutover lands
/// (`docs/phases/One_Run_Surface.md` §ORS-S00 items 2–3).
/// Do not XCTSkip / XCTExpectFailure / weaken them to go green.
final class OneRunSurfaceTeachingTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    // MARK: - Teachable corpus

    /// One agent-facing teaching string with a stable source label for failure messages.
    private struct Teachable: Equatable {
        let source: String
        let text: String
        /// Agent-facing nextAction / example only (assertion f scope).
        let isNextActionOrExample: Bool
    }

    private func collectTeachableCorpus() -> [Teachable] {
        var out: [Teachable] = []

        // --- HelpTopicRegistry (titles, summaries, bodies, sections, nextActions) ---
        for topic in HelpTopicRegistry.topics {
            let fields: [(String, String)] = [
                ("title", topic.title),
                ("summary", topic.summary),
                ("body", topic.bodyMarkdown),
            ] + topic.sections.map { ("section.\($0.id)", $0.bodyMarkdown) }
            for (field, prose) in fields {
                for cmd in Self.extractBacktickedAllnCommands(from: prose) {
                    out.append(Teachable(
                        source: "HelpTopicRegistry.\(topic.id).\(field)",
                        text: cmd,
                        isNextActionOrExample: field != "title" && field != "summary"
                    ))
                }
            }
            // relatedCommandNames are taught as selectable verbs; gate them too.
            for name in topic.relatedCommandNames {
                out.append(Teachable(
                    source: "HelpTopicRegistry.\(topic.id).relatedCommandNames",
                    text: "alln \(name)",
                    isNextActionOrExample: false
                ))
            }
            // Help nextActions (HelpNextToolStep plans).
            let plan = HelpProjector.get(
                topic: topic.id,
                contractVersion: reg.contractVersion
            ).nextToolPlan
            for step in plan {
                out.append(Teachable(
                    source: "HelpTopicRegistry.\(topic.id).nextToolPlan[\(step.order)]",
                    text: step.command,
                    isNextActionOrExample: true
                ))
            }
        }

        // --- TeachingSnippet + Bootstrap output ---
        for (idx, line) in TeachingSnippet.reflexLines.enumerated() {
            for cmd in Self.extractBacktickedAllnCommands(from: line) {
                out.append(Teachable(
                    source: "TeachingSnippet.reflexLines[\(idx)]",
                    text: cmd,
                    isNextActionOrExample: false
                ))
            }
        }
        for host in Bootstrap.Host.allCases {
            let snippet = Bootstrap.snippet(
                binaryPath: "/tmp/alln-test-binary",
                onPath: true,
                host: host
            )
            for cmd in Self.extractBacktickedAllnCommands(from: snippet) {
                out.append(Teachable(
                    source: "Bootstrap.snippet(host:\(host.rawValue))",
                    text: cmd,
                    isNextActionOrExample: false
                ))
            }
            if let preamble = host.coldStartPreamble {
                for cmd in Self.extractBacktickedAllnCommands(from: preamble) {
                    out.append(Teachable(
                        source: "Bootstrap.Host.\(host.rawValue).coldStartPreamble",
                        text: cmd,
                        isNextActionOrExample: false
                    ))
                }
            }
        }

        // --- MenuCatalog action examples + validateExamples ---
        // Mirror MenuCatalog.actionExample / actionValidateExample without
        // calling MenuCatalog.project() (which enforces model-copy bounds and
        // can fatalError on unrelated catalog drift during a teaching gate).
        let recipesById = Dictionary(uniqueKeysWithValues: reg.examples.map { ($0.id, $0) })
        for spec in reg.commands where spec.milestone == .m1 && spec.menuAction {
            let example: String
            if spec.name == "run" {
                example = "alln run \"{message}\" --team code_growth --json"
            } else {
                example = CommandDescription.example(for: spec, recipes: recipesById)
            }
            let validate: String
            if spec.name == "run" {
                validate = "alln run \"{message}\" --team code_growth --dry-run --json"
            } else if let twin = spec.freeTwinCommand, !twin.isEmpty {
                validate = twin.contains("--json") ? twin : "\(twin) --json"
            } else if example.contains("--json") {
                validate = example
            } else {
                validate = example + " --json"
            }
            out.append(Teachable(
                source: "MenuCatalog.actions[\(spec.name)].example",
                text: example,
                isNextActionOrExample: true
            ))
            out.append(Teachable(
                source: "MenuCatalog.actions[\(spec.name)].validateExample",
                text: validate,
                isNextActionOrExample: true
            ))
        }

        // --- ContractRegistry error agentAction (+ fixCommand when present) ---
        // ErrorSpec currently owns agentAction only; scan that text as the recovery teacher.
        for err in reg.errors {
            out.append(Teachable(
                source: "ContractRegistry.errors[\(err.code)].agentAction",
                text: err.agentAction,
                isNextActionOrExample: true
            ))
            for cmd in Self.extractBacktickedAllnCommands(from: err.agentAction) {
                out.append(Teachable(
                    source: "ContractRegistry.errors[\(err.code)].agentAction.command",
                    text: cmd,
                    isNextActionOrExample: true
                ))
            }
            for cmd in Self.extractBacktickedAllnCommands(from: err.explain) {
                out.append(Teachable(
                    source: "ContractRegistry.errors[\(err.code)].explain.command",
                    text: cmd,
                    isNextActionOrExample: false
                ))
            }
        }

        // --- Core nextAction factories that teach single-run read grammar ---
        // (same product surface the deletion manifest renames to `show --stream`)
        let sampleRunId = "run_ors_s00b"
        for (label, action) in [
            ("waitForTerminal", AsyncTeamNextAction.waitForTerminal(runId: sampleRunId)),
            ("fetchResult", AsyncTeamNextAction.fetchResult(runId: sampleRunId)),
            ("waitForStatus", AsyncTeamNextAction.waitForStatus(runId: sampleRunId)),
        ] {
            out.append(Teachable(
                source: "AsyncTeamNextAction.\(label)",
                text: action.command,
                isNextActionOrExample: true
            ))
        }

        // --- PilotCLI.swift (CLI target; Core tests cannot import it — read source) ---
        out.append(contentsOf: pilotCLITeachableCommands())

        // --- Registry examples + CommandDescription examples (agent-facing examples) ---
        for example in reg.examples {
            out.append(Teachable(
                source: "ContractRegistry.examples[\(example.id)]",
                text: example.command,
                isNextActionOrExample: true
            ))
        }
        for cmd in reg.commands where cmd.milestone == .m1 && cmd.visibility == .public {
            let example = CommandDescription.example(for: cmd, recipes: recipesById)
            out.append(Teachable(
                source: "CommandDescription.example[\(cmd.name)]",
                text: example,
                isNextActionOrExample: true
            ))
        }

        return out
    }

    /// PilotCLI lives under AllnighterCLI (not linked into this target). Hostile
    /// gate still owns those teaching strings by reading the source SSOT.
    private func pilotCLITeachableCommands() -> [Teachable] {
        let thisFile = URL(fileURLWithPath: #filePath)
        // …/Tests/AllnighterCoreTests/OneRunSurfaceTeachingTests.swift
        // → …/Sources/AllnighterCLI/PilotCLI.swift
        let pilotURL = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AllnighterCLI/PilotCLI.swift")
        guard let source = try? String(contentsOf: pilotURL, encoding: .utf8) else {
            // Vacuous-pass hole (ORS-S00c): a MISSING_SOURCE sentinel skipped every deny
            // assertion. Unreadable source must fail loud, never silently drop the family.
            XCTFail(
                "ORS teaching gate: unreadable PilotCLI.swift — attempted path: \(pilotURL.path)"
            )
            return []
        }
        // Extract double-quoted string literals that teach an `alln …` invocation.
        let pattern = try! NSRegularExpression(pattern: #""(alln [^"]+)""#)
        let ns = source as NSString
        let matches = pattern.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var out: [Teachable] = []
        for (idx, match) in matches.enumerated() {
            let text = ns.substring(with: match.range(at: 1))
            out.append(Teachable(
                source: "PilotCLI.swift.allnString[\(idx)]",
                text: text,
                isNextActionOrExample: true
            ))
        }
        return out
    }

    // MARK: - Extraction helpers

    private static func extractBacktickedAllnCommands(from prose: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"`(alln[^`]*)`"#)
        let ns = prose as NSString
        let matches = pattern.matches(in: prose, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "alln" }
    }

    /// Strip optional `[…]` / `<…>` grammar and collapse whitespace so prose
    /// examples like `alln show <run-id> --json` resolve to `show`.
    private static func normalizeInvocation(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let open = s.range(of: "["), let close = s.range(of: "]", range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound..<close.upperBound)
        }
        while let open = s.range(of: "<"), let close = s.range(of: ">", range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func offenders(
        in corpus: [Teachable],
        where predicate: (Teachable) -> Bool
    ) -> [String] {
        corpus.filter(predicate).map { "\($0.source): \($0.text)" }
    }

    private func command(_ name: String) -> ContractRegistry.CommandSpec? {
        reg.commands.first { $0.name == name }
    }

    private func flag(_ name: String, on command: ContractRegistry.CommandSpec) -> ContractRegistry.FlagSpec? {
        command.flags.first { $0.name == name }
    }

    // MARK: - PART 1: Hostile teaching gate

    /// Vacuous-pass guard (ORS-S00c): deny tests skip non-`alln` / non-matching
    /// strings. If the corpus is empty or a claimed family contributes nothing,
    /// every deny test would go green having policed nothing.
    func testTeachableCorpusIsActuallyPopulated() {
        let corpus = collectTeachableCorpus()
        XCTAssertFalse(
            corpus.isEmpty,
            "ORS teaching gate: teachable corpus must be non-empty (empty corpus = vacuous pass on every deny test)"
        )

        // Each source family this gate claims to police must contribute ≥1 entry.
        let families: [(name: String, matches: (Teachable) -> Bool)] = [
            ("HelpTopicRegistry", { $0.source.hasPrefix("HelpTopicRegistry.") }),
            ("TeachingSnippet", { $0.source.hasPrefix("TeachingSnippet.") }),
            ("Bootstrap", {
                $0.source.hasPrefix("Bootstrap.snippet") || $0.source.hasPrefix("Bootstrap.Host.")
            }),
            ("MenuCatalog action examples", { $0.source.hasPrefix("MenuCatalog.actions[") }),
            ("ContractRegistry errors (agentAction/fixCommand)", {
                $0.source.hasPrefix("ContractRegistry.errors[")
            }),
            ("PilotCLI.swift", { $0.source.hasPrefix("PilotCLI.swift") }),
        ]
        for family in families {
            let count = corpus.filter(family.matches).count
            XCTAssertGreaterThan(
                count,
                0,
                "ORS teaching gate: source family \(family.name) contributed 0 teachable entries (vacuous pass risk)"
            )
        }

        // CANARY (flipped ORS-S03a): PilotCLI no longer teaches `team status`;
        // family still contributes ≥1 entry and contains NO "team status".
        // Proves the extractor still reads PilotCLI.swift.
        let pilotEntries = corpus.filter { $0.source.hasPrefix("PilotCLI.swift") }
        XCTAssertFalse(
            pilotEntries.isEmpty,
            "ORS teaching gate CANARY: PilotCLI family must still contribute ≥1 teachable entry"
        )
        let pilotHasTeamStatus = pilotEntries.contains { $0.text.contains("team status") }
        XCTAssertFalse(
            pilotHasTeamStatus,
            "ORS teaching gate CANARY: PilotCLI must not teach \"team status\" after ORS-S03a:\n\(pilotEntries.map(\.text).joined(separator: "\n"))"
        )
    }

    func testTeachableCorpusDeniesTeamStatus() {
        let hits = offenders(in: collectTeachableCorpus()) { $0.text.contains("team status") }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: retired `team status` must not be taught:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testTeachableCorpusDeniesTeamResult() {
        let hits = offenders(in: collectTeachableCorpus()) { $0.text.contains("team result") }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: retired `team result` must not be taught:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testTeachableCorpusDeniesWaitFor() {
        // Scope correction (ORS-S00c), not a narrowing to reach green.
        // Packet cutover table `delivery.path=wait` row (One_Run_Surface.md):
        // "Loop/relay waiters are out of scope for this packet." The waiter
        // deletion is scoped to retired single-run read grammar (`team status` /
        // `team result` + `--wait-for`), not `alln loop status … --wait-for`.
        let hits = offenders(in: collectTeachableCorpus()) { entry in
            guard entry.text.contains("--wait-for") else { return false }
            return entry.text.contains("team status") || entry.text.contains("team result")
        }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: retired single-run `--wait-for` (team status|result) must not be taught:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testTeachableCorpusDeniesPersisted() {
        let hits = offenders(in: collectTeachableCorpus()) { $0.text.contains("--persisted") }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: retired `--persisted` status mode must not be taught:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testTeachableCorpusDeniesSupportDirectoryRunPaths() {
        let hits = offenders(in: collectTeachableCorpus()) {
            $0.text.contains("run.json") || $0.text.contains("events.jsonl")
        }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: support-directory run paths (run.json / events.jsonl) must not be taught:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testAgentFacingNextActionsAndExamplesDenyLatestAndFull() {
        // Scope correction (ORS-S00c), not a narrowing to reach green.
        // Packet (One_Run_Surface.md): "`latest` and `--full` stay for humans but
        // are banned from agent teaching and `nextActions`." — as a second
        // snapshot shape of the single-run read surface (`alln show …`). Other
        // commands' grammar (`alln doctor --full`, `alln artifact show latest`)
        // is out of scope; only resolved command `show` is policed.
        let hits = offenders(in: collectTeachableCorpus()) { entry in
            guard entry.isNextActionOrExample else { return false }
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("alln ") || trimmed.hasPrefix("`alln ") else { return false }
            let raw = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            let invocation = Self.normalizeInvocation(raw)
            guard invocation.hasPrefix("alln ") else { return false }
            guard ContractRegistry.resolveCommandName(from: invocation, registry: reg) == "show"
            else { return false }
            let text = entry.text
            // Token-aware: bare "latest" as a run selector, or the `--full` flag.
            let hasLatest =
                text.range(of: #"\blatest\b"#, options: .regularExpression) != nil
            let hasFull =
                text.contains("--full")
                || text.range(of: #"\s--full\b"#, options: .regularExpression) != nil
                || text.hasSuffix(" --full")
            return hasLatest || hasFull
        }
        XCTAssertTrue(
            hits.isEmpty,
            "ORS teaching gate: agent nextAction/example must not teach `alln show` with `latest` or `--full`:\n\(hits.joined(separator: "\n"))"
        )
    }

    func testEveryAllnTeachableStringResolvesToRegisteredCommand() {
        var failures: [String] = []
        for entry in collectTeachableCorpus() {
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only gate concrete `alln …` invocations (not free-form recovery prose).
            guard trimmed.hasPrefix("alln ") || trimmed.hasPrefix("`alln ") else { continue }
            let raw = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            let invocation = Self.normalizeInvocation(raw)
            guard invocation.hasPrefix("alln ") else { continue }
            // Meta templates like `alln <command> --help` have no resolvable verb.
            let rest = String(invocation.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty || rest.hasPrefix("-") { continue }
            if ContractRegistry.resolveCommandName(from: invocation, registry: reg) == nil {
                failures.append("\(entry.source): unresolved `\(raw)` (normalized: \(invocation))")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "ORS teaching gate: every taught `alln …` must name a registered command:\n\(failures.joined(separator: "\n"))"
        )
    }

    // MARK: - PART 2: `show --stream` framing lock (registry/schema only)

    func testShowStreamAndRunStreamDeclareTheSameFrameSchema() throws {
        let show = try XCTUnwrap(command("show"), "ORS: canonical `show` must be registered")
        let run = try XCTUnwrap(command("run"), "ORS: `run` must be registered")
        let showStream = try XCTUnwrap(
            flag("stream", on: show),
            "ORS: `show` must declare `--stream` (canonical reattach surface)"
        )
        let runStream = try XCTUnwrap(
            flag("stream", on: run),
            "ORS: `run` must declare `--stream`"
        )

        // Existing NDJSON event set + terminal frames (ContractRegistry m1Events).
        let eventNames = Set(reg.events.map(\.name))
        XCTAssertTrue(
            eventNames.contains("teamRunCompleted"),
            "ORS: one run-event frame schema must include teamRunCompleted"
        )
        XCTAssertTrue(
            eventNames.contains("teamRunFailed"),
            "ORS: one run-event frame schema must include teamRunFailed"
        )

        // Exactly one registered frame schema for run events — not two parallel catalogs.
        // Both stream flags must describe the same terminal frames (shared schema text).
        for (label, streamFlag) in [("show", showStream), ("run", runStream)] {
            XCTAssertTrue(
                streamFlag.summary.contains("teamRunCompleted"),
                "ORS: \(label) --stream must declare teamRunCompleted terminal frame (got: \(streamFlag.summary))"
            )
            XCTAssertTrue(
                streamFlag.summary.contains("teamRunFailed"),
                "ORS: \(label) --stream must declare teamRunFailed terminal frame (got: \(streamFlag.summary))"
            )
        }
        XCTAssertEqual(
            showStream.summary,
            runStream.summary,
            "ORS: `show --stream` and `run --stream` must declare the SAME frame schema text (no parallel framing)\nshow: \(showStream.summary)\nrun:  \(runStream.summary)"
        )
    }

    func testShowStreamContractStatesSnapshotReplayLiveAndOneTerminal() throws {
        let show = try XCTUnwrap(command("show"), "ORS: canonical `show` must be registered")
        let stream = try XCTUnwrap(
            flag("stream", on: show),
            "ORS: `show` must declare `--stream`"
        )
        // Registry/docs projection is the only stream-contract surface in Core today.
        let contract = [
            stream.summary,
            CommandProjection.streamFramingMarkdown,
            show.summary,
        ].joined(separator: "\n")
        let lower = contract.lowercased()

        let requirements: [(String, [String])] = [
            ("immediate snapshot first", ["immediate snapshot", "snapshot first", "current run snapshot", "emits the current"]),
            ("bounded replay", ["bounded replay", "replay a bounded", "bounded recent", "replay"]),
            ("live follow", ["live follow", "follows new", "live events", "live follow", "follow new"]),
            ("exactly one terminal frame", ["exactly one terminal", "exactly one of", "one terminal event", "one terminal frame"]),
        ]
        var missing: [String] = []
        for (name, needles) in requirements {
            let hit = needles.contains { lower.contains($0.lowercased()) }
            if !hit {
                missing.append("\(name) (need one of: \(needles.joined(separator: " | ")))")
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "ORS: `show --stream` contract must state snapshot → replay → live → one terminal.\nMissing: \(missing.joined(separator: "; "))\nContract text:\n\(contract)"
        )
    }

    func testShowStreamDeclaresAttentionExitWithNonShowRunRecovery() throws {
        let show = try XCTUnwrap(command("show"), "ORS: canonical `show` must be registered")
        let stream = try XCTUnwrap(
            flag("stream", on: show),
            "ORS: `show` must declare `--stream`"
        )
        let contract = (stream.summary + "\n" + CommandProjection.streamFramingMarkdown).lowercased()
        XCTAssertTrue(
            contract.contains("attention"),
            "ORS: `show --stream` must declare a bounded attention-required exit (got stream summary: \(stream.summary))"
        )

        // Recovery nextAction kind must be declared and must NOT be showRun
        // (self-referential next action == poll loop).
        let attentionKinds = reg.nextActionKinds.filter { kind in
            let blob = (kind.kind + " " + kind.summary).lowercased()
            return blob.contains("attention")
                || blob.contains("blocker")
                || blob.contains("vendor")
                || blob.contains("budget")
                || kind.kind == "inspectBlocker"
                || kind.kind == "inspectStall"
        }
        XCTAssertFalse(
            attentionKinds.isEmpty,
            "ORS: attention-required recovery nextAction kind must be registered in nextActionKinds (none found)"
        )
        for kind in attentionKinds {
            XCTAssertNotEqual(
                kind.kind,
                "showRun",
                "ORS: attention recovery nextAction kind must NOT be `showRun` (self-referential poll loop); offender kind=\(kind.kind) summary=\(kind.summary)"
            )
        }
        // Closed catalog must not list showRun as the attention recovery path.
        let showRun = reg.nextActionKinds.first { $0.kind == "showRun" }
        if let showRun {
            XCTAssertFalse(
                showRun.summary.lowercased().contains("attention"),
                "ORS: showRun must not be the attention-required recovery path (summary: \(showRun.summary))"
            )
        }
    }

    func testShowStreamPropagatesTerminalExitClassUnconditionally() throws {
        let show = try XCTUnwrap(command("show"), "ORS: canonical `show` must be registered")
        let stream = try XCTUnwrap(
            flag("stream", on: show),
            "ORS: `show` must declare `--stream`"
        )
        let flagNames = Set(show.flags.map(\.name))
        // No opt-in flag (gh run watch --exit-status style). Propagation is unconditional.
        XCTAssertFalse(
            flagNames.contains("exit-status"),
            "ORS: `show` must not require `--exit-status` opt-in for terminal exit class"
        )
        XCTAssertFalse(
            flagNames.contains("exit-class"),
            "ORS: `show` must not require `--exit-class` opt-in for terminal exit class"
        )

        let summary = stream.summary.lowercased()
        let framing = CommandProjection.streamFramingMarkdown.lowercased()
        let documents =
            (summary.contains("exit") && (summary.contains("terminal") || summary.contains("unconditional") || summary.contains("exit class")))
            || (framing.contains("exit") && (framing.contains("terminal") || framing.contains("unconditional") || framing.contains("exit class")))
            || summary.contains("unconditional")
            || framing.contains("propagat")
        XCTAssertTrue(
            documents,
            "ORS: `show --stream` must declare unconditional terminal exit-class propagation (no opt-in flag).\nstream.summary: \(stream.summary)\nstreamFramingMarkdown: \(CommandProjection.streamFramingMarkdown)"
        )
    }
}
