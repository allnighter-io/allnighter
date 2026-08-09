import Foundation

/// The built-in lane-scoped teams — product assets shipped with Allnighter
/// (Team_Catalog §Built-in Team Manifest Index). Built-in ids are an
/// immutable public contract once used in history/reproduce commands; built-ins
/// cannot be edited directly — users duplicate them to customize.
public enum BuiltInTeams {

    public static let all: [TeamPreset] = [
        buildCore, buildBugHuntMin, buildBugHunt, buildBugHuntMax, buildGUIBugHunt, buildSecurityReview,
        buildSpecReviewMin, buildDocReview, buildSpecReview, buildSpecReviewMax, buildReleaseProof,
        buildAIReadiness,
        buildGrowthMin, buildGrowth, buildGrowthMax, buildFusion,
        defaultChat, executionPlaybook,
        designMin, designCore, designMax, designPremiumPolish, designUsabilityTriage,
        copyCore, copyLandingPage,
        signalPostToProject, signalWhatToBuildNext
    ]

    private static let byID: [String: TeamPreset] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func team(_ id: String) -> TeamPreset? { byID[id] }
    public static func teams(in lane: WorkLane) -> [TeamPreset] { all.teams(in: lane) }

    // MARK: - Model routing (fan-out diversity policy)

    /// Synthesis Lead — Fable 5 (flagship-only). Codex Sol is the strategic
    /// deputy (never Cursor Sol — paid quota, manual opt-in only).
    private static let leadFlagship = "model_fable"
    private static let opus = "model_opus"
    /// Default worker anchor for mutating Auto / Build a Slice (Cursor).
    private static let composer = "model_cursor_composer_25"
    private static let gptSol = "model_gpt_sol"
    private static let gemini = "model_gemini"
    private static let sonnet = "model_sonnet"
    private static let kimi = "model_kimi_k3"
    private static let cursorGrok = "model_cursor_grok_45"
    private static let cursorAuto = "model_cursor_auto"
    /// External / X / web research scout (also high/mid value in rotations).
    private static let grok = "model_grok"
    /// OpenRouter Fusion budget panel (DRACO 64.7%): local catalog ids for
    /// Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro.
    private static let fusionDeepseek = "model_opencode_deepseek_v4_pro"
    private static let fusionPanelPreference = [gemini, "model_kimi_k27", fusionDeepseek]

    // MARK: - Builders

    /// One worker row. Row id defaults to the skill id (unique within a team).
    private static func row(
        _ skillId: String, _ purpose: TeamAgentPurpose,
        preferred: String? = nil, required: Bool = true,
        fallbacks: [String] = [],
        tags: [ModelCapabilityTag] = [], fallback: ModelFallbackPolicy = .anyReady
    ) -> TeamAgentSpec {
        TeamAgentSpec(id: skillId, skillId: skillId, purpose: purpose,
                       preferredModelId: preferred,
                       fallbackModelIds: fallbacks.isEmpty ? nil : fallbacks,
                       requiredCapabilityTags: tags,
                       fallbackPolicy: fallback, required: required)
    }

    /// One worker row expressing NEED, not identity (Law 3,
    /// Team_Catalog_Normalization.md): no `preferredModelId`, just the
    /// capability the seat requires. The shared resolver fills it from the
    /// ready bench — declaration order gives earlier rows in a team's row list
    /// first pick of the strongest ready capable model (the old "strategic
    /// seat" judgment now falls out of row order + rank instead of a pinned
    /// model id), later rows spread to the next distinct capable model
    /// (cross-row diversity), and the pool degrades to reuse rather than
    /// blocking once every capable model is claimed.
    /// `preferred` (CN-S06 / Law 3): capability tags that REORDER candidates
    /// within a caliber band — a ready specialist carrying them takes the seat
    /// ahead of an equal-caliber generalist — but NEVER filter and NEVER beat
    /// caliber. Empty = no preference (identical staffing to today).
    private static func needRow(
        _ skillId: String, _ purpose: TeamAgentPurpose,
        tags: [ModelCapabilityTag], required: Bool = true,
        preferred: [ModelCapabilityTag] = []
    ) -> TeamAgentSpec {
        var spec = row(skillId, purpose, required: required, tags: tags, fallback: .anyReady)
        spec.preferredCapabilityTags = preferred
        return spec
    }

    private static func needRows(
        _ specs: [(String, TeamAgentPurpose)], tags: [ModelCapabilityTag],
        preferred: [ModelCapabilityTag] = []
    ) -> [TeamAgentSpec] {
        specs.map { needRow($0.0, $0.1, tags: tags, preferred: preferred) }
    }

    /// Fable synthesizes; when Fable is unavailable, **Codex Sol** (`model_gpt_sol`)
    /// is the designated deputy lead for EVERY team. Cursor Sol is never in this
    /// chain (paid Cursor quota — manual opt-in only). Fallbacks stay on
    /// subscription CLI homes; broad `.strongestReady` still filters
    /// `neverAutomaticSubstituteIds` in the resolver.
    private static func synthesisLead(_ writer: String, dissent: DissentPolicy = .preserveDissent) -> TeamLeadSpec {
        TeamLeadSpec(
            skillId: writer,
            preferredModelId: leadFlagship,
            fallbackModelIds: [
                gptSol, opus, kimi, cursorGrok, grok,
                composer, sonnet, gemini, cursorAuto
            ],
            fallbackPolicy: .strongestReady,
            dissentPolicy: dissent)
    }

    /// Every built-in carries one mandatory Team Lead (synthesizer). Effort scales
    /// the crew, never the Lead.
    private static func make(
        id: String, name: String, lane: WorkLane, output: TeamOutputKind,
        defaultEffort: EffortLevel, isDefault: Bool = false, description: String,
        scout: TeamAgentSpec? = nil,
        rows: [TeamAgentSpec], writer: String, dissent: DissentPolicy = .preserveDissent,
        lead: TeamLeadSpec? = nil,
        mutating: Bool = false, executionSourceId: String? = nil,
        typeTags: [String] = [], starters: [String] = []
    ) -> TeamPreset {
        TeamPreset(
            id: id, displayName: name, lane: lane, description: description, outputKind: output,
            mutating: mutating,
            executionSourceId: executionSourceId,
            defaultEffort: defaultEffort, isDefaultForLane: isDefault, scout: scout, agentSpecs: rows,
            lead: lead ?? synthesisLead(writer, dissent: dissent),
            typeTags: typeTags, starterPrompts: starters, builtIn: true, version: 1)
    }

    /// The Signal scout row: Grok reads / researches X and public web sources first.
    /// Cursor Grok is an explicit ordered fallback (same mind, Cursor route) when
    /// the Grok CLI seat is down — never a silent broad cross-CLI fill.
    static let signalScoutGrok = TeamAgentSpec(
        id: "signal_source_reader", skillId: "signal_source_reader", purpose: .answer,
        preferredModelId: grok, fallbackModelIds: [cursorGrok], fallbackPolicy: .laneCapable)

    /// Canonical interpreter preference: Grok (web-aware), GPT-5.6, then Gemini.
    static let signalInterpreterPreference = [grok, gptSol, gemini]

    // MARK: - Code teams

    static let buildCore = make(
        id: "code_plan", name: "Plan", lane: .code, output: .plan, defaultEffort: .med, isDefault: true,
        description: "Turn a rough idea or build into an implementable plan — scope, architecture, risks, and concrete proof.",
        // first_principles_builder declared first so it claims the strongest ready
        // model (declaration order + caliber, not a pinned identity — Law 3).
        rows: needRows([
            ("first_principles_builder", .answer),
            ("product_architect", .answer),
            ("proof_planner", .answer),
            ("code_maintainer", .answer),
            ("scope_steward", .review),
            ("security_privacy_reviewer", .review),
            ("contrarian_reviewer", .review)
        ], tags: [.code]),
        writer: "plan_writer_build",
        typeTags: ["plan", "scope", "architecture", "design-doc", "breakdown"],
        starters: ["Turn this rough idea into an implementable plan with scope and proof.",
                   "Plan the smallest correct slice for <feature>."])

    /// Bug Hunt Min — the fastest credible cause hunt: reproduce, name the truth
    /// owner (the root-cause seat), plan the smallest fix and the proof that would
    /// catch it. Bug Hunt Default carries no reviewer rows, so there is no A/B judge
    /// pair for Min to preserve. Depth splits charters rather than deleting them
    /// (`docs/operations/Spec_Review.md` §Depth splits charters): Min does not drop
    /// `regression_guard`'s job, it folds it into `bug_min_fix_planner` as a second
    /// named pass, so no Min run ships a fix with no proof thinking behind it. Same
    /// writer/output as the family (Team_Catalog_Normalization.md, Min pattern).
    static let buildBugHuntMin = make(
        id: "code_bug_hunt_min", name: "Bug Hunt Min", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Fastest credible cause hunt: reproduce it, name the truth owner, plan the smallest correct fix and the test that would have caught it.",
        rows: needRows([
            ("bug_reproducer", .answer),
            ("truth_owner_mapper", .answer),
            ("bug_min_fix_planner", .answer)
        ], tags: [.code]),
        writer: "bug_packet_writer",
        typeTags: ["bug-hunt-min"],
        starters: ["Quick bug hunt: find the cause of <broken behavior> and the smallest fix."])

    /// Bug Hunt — bare/default depth tier. Lean 4-seat roster; two-judge A/B
    /// proved it ties the heavier roster on deliverable quality at lower seat
    /// cost, so it is the everyday choice (Team_Depth_Naming).
    static let buildBugHunt = make(
        id: "code_bug_hunt", name: "Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Find the real cause of a bug and plan the smallest correct fix: reproduce, name the truth owner, fix at the right level, prove it.",
        rows: needRows([
            ("bug_reproducer", .answer),
            ("truth_owner_mapper", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer)
        ], tags: [.code]),
        writer: "bug_packet_writer",
        typeTags: ["bug", "crash", "defect", "cause", "fix", "regression"],
        starters: ["Find the real cause of <broken behavior> and plan the smallest correct fix."])

    /// Bug Hunt Max — escalation depth for nasty bugs: seam-crossing, hidden/
    /// stale state, and bugs that survived earlier fix attempts. Keeps the core
    /// 4 plus specialists for those failure modes, with two anti-fixation
    /// reviewers — Contrarian (wrong *theory*) and Fix Altitude (wrong *level*)
    /// — and the carry-law writer so specialist evidence is never flattened in
    /// synthesis. Description keeps the deep-trace Max framing (Team_Depth_Naming).
    static let buildBugHuntMax = make(
        id: "code_bug_hunt_max", name: "Bug Hunt Max", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Escalation for nasty bugs — seam-crossing, hidden state, and fixes that keep failing. Deeper trace, state, and wrong-level checks.",
        rows: needRows([
            ("bug_reproducer", .answer),
            ("truth_owner_mapper", .answer),
            ("trace_mapper", .answer),
            ("state_skeptic", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer),
            ("contrarian_root_cause", .review),
            ("fix_altitude_reviewer", .review)
        ], tags: [.code]),
        writer: "bug_packet_writer",
        typeTags: ["bug-hunt-max", "nasty", "deep", "seam", "hidden-state"],
        starters: ["This bug has resisted earlier fixes — find the real cause and the right-level fix for <broken behavior>."])

    static let buildGUIBugHunt = make(
        id: "code_gui_bug_hunt", name: "GUI Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Fix visible native-app breakage with rendered proof, layout-watcher review, and the right truth owner.",
        rows: needRows([
            ("gui_bug_reproducer", .answer),
            ("gui_proof_guard", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer),
            ("truth_owner_mapper", .answer),
            ("state_skeptic", .answer),
            ("change_impact_reviewer", .answer),
            ("gui_layout_reviewer", .review),
            ("contrarian_root_cause", .review)
        ], tags: [.code]),
        writer: "gui_bug_packet_writer",
        typeTags: ["gui", "ui", "visual", "layout", "rendered", "clipping"],
        starters: ["The UI is visibly broken — <what looks wrong>. Find the cause and fix it with rendered proof."])

    static let buildSecurityReview = make(
        id: "code_security_review", name: "Security Review", lane: .code, output: .securityRegister, defaultEffort: .high,
        description: "Evaluate privacy, credentials, permissions, exposure, and destructive operations with small-team shipping judgment.",
        rows: needRows([
            ("boundary_mapper", .answer),
            ("secrets_reviewer", .answer),
            ("permission_reviewer", .answer),
            ("data_flow_reviewer", .answer),
            ("abuse_case_reviewer", .answer),
            ("dependency_injection_reviewer", .review),
            ("security_fix_prioritizer", .review)
        ], tags: [.code], preferred: [.security]),
        writer: "security_register_writer", dissent: .riskRegister,
        typeTags: ["security", "credentials", "permissions", "exposure", "secrets", "vuln"],
        starters: ["Review this change for credential, permission, exposure, and destructive-op risks before I ship."])

    // MARK: - Growth (same prompt, diverse models)

    /// Growth Min — up to 4 diverse models, no per-team model list: triangulation
    /// fills from the ready bench strongest-first (Law 3), reserving the Lead's
    /// model, so it stays useful with no Claude/ChatGPT subscription required.
    static let buildGrowthMin = make(
        id: "code_growth_min", name: "Growth Min", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Fast growth read: up to 4 diverse models (a flagship when you have one) hunt the wedge that makes X builders love it — kept simple and on-core. Runs on whatever's ready; drops a seat rather than doubling up.",
        rows: [
            TeamAgentSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           requiredCapabilityTags: [.code],
                           count: 4, triangulate: true)
        ],
        writer: "growth_writer",
        typeTags: ["growth-min"],
        starters: [
            "Growth: how do we make X builders LOVE this and spread it, kept simple and on-core? Find the wedge, the shareable artifact, and the simplest lovable version."]
    )

    /// Growth — the everyday default. Up to 6 genuinely different frontier models
    /// on ONE shared growth-hacker prompt (the diversity is the model, not the lens);
    /// a first-principles synthesizer that hunts the BEST idea — outlier or consensus —
    /// and never rewards agreement for its own sake. Triangulation fills strongest-
    /// first from the ready bench (Law 3) — no per-team model list, so flagships are
    /// recruited as workers automatically whenever they're ready.
    static let buildGrowth = make(
        id: "code_growth", name: "Growth", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Make X builders and influencers LOVE a feature: up to 6 diverse models — flagships recruited as workers when ready (never benched for the Lead) — swing big on the same growth question; Fable synthesizes and picks the highest-leverage wedge that stays on-core and simple, valuing the breakout outlier over safe consensus. Runs on whatever's ready; drops a seat rather than doubling up.",
        rows: [
            TeamAgentSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           requiredCapabilityTags: [.code],
                           count: 6, triangulate: true)
        ],
        writer: "growth_writer",
        typeTags: ["growth"],
        starters: [
            "Growth: how do we make the X builders and influencers who matter LOVE this — enough to use it daily and tell others — while keeping it simple and true to the core? Find the wedge, the aha, the shareable artifact, and what to cut.",
            "Review docs/phases/<Feature>.md with Growth: the loved wedge, the viral loop, the simplest lovable version, and the breakout bet."]
    )

    /// Growth Max — the same triangulated roster plus an X/web research scout that
    /// reads what is actually spreading in the category right now, so the ideas are
    /// grounded in live signal, not vibes. Grok is preferred for the scout seat on a
    /// structural fact (it is the web-aware CLI, same reasoning as the Signal scout),
    /// not a per-team preference list — it still degrades to any lane-capable model.
    static let buildGrowthMax = make(
        id: "code_growth_max", name: "Growth Max", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Deep growth read: an X/web signal scout on what is spreading now, then up to 8 diverse models on the wedge — every flagship and idle model recruited when ready (Sol, GPT-5.6, Opus, Sonnet, Composer…) — and a synthesizer that prizes the breakout outlier over safe consensus. Drops a seat rather than doubling up.",
        scout: row("signal_source_reader", .answer, preferred: grok,
                   fallbacks: [cursorGrok], fallback: .laneCapable),
        rows: [
            TeamAgentSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           requiredCapabilityTags: [.code],
                           count: 8, triangulate: true)
        ],
        writer: "growth_writer",
        typeTags: ["growth-max"],
        starters: [
            "Growth Max: scout what is spreading in the category on X now, then find the wedge that makes builders LOVE this and the shareable viral loop — kept simple and on-core."]
    )

    /// Fusion — OpenRouter's published control configuration: the same prompt on a
    /// fixed three-model panel, one Lead merges the answers. Not the recommended
    /// default — the baseline you can re-run beside differentiated teams like
    /// Spec Review. OpenRouter scored this panel at 64.7% on DRACO deep research
    /// (Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro, synthesized by Opus 4.8).
    static let buildFusion = make(
        id: "fusion", name: "Fusion", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "OpenRouter Fusion control: Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro on the same prompt, synthesized by Opus 4.8 — 64.7% on DRACO deep research (openrouter.ai/blog/announcements/fusion-beats-frontier/). Baseline control, not the recommended default.",
        rows: [
            TeamAgentSpec(id: "fusion_seats", skillId: "fusion_panelist", purpose: .answer,
                           count: 3, triangulate: true,
                           triangulatePreferenceIds: fusionPanelPreference)
        ],
        writer: "fusion_writer",
        lead: TeamLeadSpec(
            skillId: "fusion_writer",
            preferredModelId: opus,
            fallbackModelIds: [gptSol, leadFlagship, kimi, cursorGrok, grok, composer, sonnet, gemini, cursorAuto],
            fallbackPolicy: .strongestReady,
            dissentPolicy: .preserveDissent),
        typeTags: ["fusion", "control", "deep-research"],
        starters: [
            "Answer this question thoroughly — factual accuracy, breadth, citations where external facts matter. Same prompt OpenRouter sent to its Fusion budget panel (64.7% on DRACO)."])

    /// Spec Review Min — the smallest useful cross-CLI panel. Rows express NEED
    /// (capability), not identity, so it stays useful without Claude or ChatGPT —
    /// the resolver spreads distinct models across the three lenses itself (Law 3;
    /// no exemption for locked families).
    ///
    /// Depth splits charters; it never deletes them
    /// (`docs/operations/Spec_Review.md` §Depth splits charters). Min does NOT run
    /// the Default's specialist prompts minus two seats — that would ship four
    /// vacancies nobody covers. It runs three BUNDLED charters (premise / evidence
    /// / delivery), each enumerating the absorbed passes, so the wrong-thing and
    /// wrong-instrument questions are present at every depth.
    static let buildSpecReviewMin = make(
        id: "code_spec_review_min", name: "Spec Review Min", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "A lean Spec Review — three seats wearing two hats each: premise + rival, proof audit + proof design, scope + buildability + contract. Lead emits Lead Call (Ready|Partial) then craft body — not a founder checklist.",
        rows: needRows([
            ("spec_min_premise_reviewer", .answer),
            ("spec_min_proof_auditor", .answer),
            ("spec_min_delivery_steward", .answer)
        ], tags: [.code]),
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["spec-review-min"],
        starters: [
            "Run a lean Spec Review on the named spec. Workers critique only (do not edit repo files). Lead emits Lead Call (Ready|Partial + locked leans + contrarian flags) then craft body — never Not ready / founder homework."]
    )

    /// Doc Review — one model, one doc, no panel. Same read-only posture as Spec
    /// Review; no Lead synthesis pass (`isSoloAnswerTeam`).
    static let buildDocReview = make(
        id: "code_doc_review", name: "Doc Review", lane: .code,
        output: .plan, defaultEffort: .med,
        description: "One model reviews one doc — critique only, no repo writes, no mutator queue.",
        rows: needRows([
            ("doc_reviewer", .answer)
        ], tags: [.code]),
        writer: SkillCatalog.docReviewerSkillId,
        lead: TeamLeadSpec(
            skillId: SkillCatalog.docReviewerSkillId,
            fallbackPolicy: .strongestReady),
        typeTags: ["doc-review", "doc", "feedback", "read-only"],
        starters: [])

    /// Spec Review — the everyday default. Five independent lenses; declaration
    /// order gives the first-principles lens first pick of the strongest ready
    /// model (the old Sol pin, now expressed as caliber + order, not identity).
    static let buildSpecReview = make(
        id: "code_spec_review", name: "Spec Review", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "Harden a feature or phase spec before you build. Lead emits Lead Call (Ready|Partial + locked leans) then Spec Review craft body.",
        rows: needRows([
            ("spec_first_principles_reviewer", .answer),
            ("spec_doc_hygiene_reviewer", .answer),
            ("spec_contract_auditor", .answer),
            ("spec_proof_planner", .answer),
            ("spec_contrarian_reviewer", .review)
        ], tags: [.code]),
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["spec-review", "spec", "review", "harden", "critique", "premise"],
        starters: [
            "Harden the named spec. Workers critique only (do not edit repo files). Lead emits Lead Call Ready|Partial with locked leans and contrarian flags — no Not ready, no founder checklist.",
            "Harden docs/phases/<Spec>.md: premise, contract, proof, cuts. Exit = Lead Call + craft body, not a rewritten phase doc dump."]
    )

    /// Spec Review Max — the full launch/hard-case panel: eight blind lenses spanning
    /// premise, operations, contract, proof, measurement, scope, simplicity, and a
    /// rival approach. Max is where the instrument audit earns a standalone seat:
    /// every other lens interrogates the subject, `measurement_auditor` interrogates
    /// the evidence itself (`docs/operations/Spec_Review.md` §4).
    static let buildSpecReviewMax = make(
        id: "code_spec_review_max", name: "Spec Review Max", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "Full-depth Spec Review for launch and hard specs, including a standalone measurement audit of the proof itself. Lead emits Lead Call (Ready|Partial) then craft body.",
        scout: row("spec_outside_scout", .answer, preferred: grok,
                   fallbacks: [cursorGrok], fallback: .laneCapable),
        rows: needRows([
            ("spec_first_principles_reviewer", .answer),
            ("spec_doc_hygiene_reviewer", .answer),
            ("spec_contract_auditor", .answer),
            ("spec_proof_planner", .answer),
            ("measurement_auditor", .answer),
            ("spec_scope_steward", .answer),
            ("spec_hype_skeptic", .review),
            ("spec_contrarian_reviewer", .review)
        ], tags: [.code]),
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["spec-review-max", "launch"],
        starters: [
            "Run Spec Review Max on the named spec. Workers critique only (do not edit repo files). Lead emits Lead Call Ready|Partial with locked leans — never Not ready / founder homework.",
            "Harden docs/phases/<Spec>.md at full depth. Exit = Lead Call + craft body, not a full doc rewrite."]
    )

    /// Release Proof — the team that decides whether the owner-visible claim is true.
    /// Every other seat here reads the code and treats the suite as the instrument;
    /// `measurement_auditor` treats the suite as the subject, which is the only way
    /// a green-but-undiscriminating check gets caught at closeout.
    static let buildReleaseProof = make(
        id: "code_release_proof", name: "Release Proof", lane: .code, output: .proofPacket, defaultEffort: .high,
        description: "Before a slice closes, prove that the owner-visible claim is actually true — and that the proof itself could have failed.",
        // acceptance_auditor declared first so it claims the strongest ready model.
        rows: needRows([
            ("acceptance_auditor", .answer),
            ("measurement_auditor", .answer),
            ("test_runner_planner", .answer),
            ("risk_register", .review),
            ("edge_case_hunter", .answer),
            ("contract_drift_checker", .answer),
            ("demo_narrator", .review)
        ], tags: [.code]),
        writer: "proof_packet_writer", dissent: .riskRegister,
        typeTags: ["proof", "release", "done", "verify", "acceptance"],
        starters: ["Prove this slice is actually done before I believe it."])

    /// AI Readiness — eight parallel blind answer seats + one Lead writer.
    /// Read-only advisory; never writes to the repo. Team output is a typed
    /// AIReadinessReport (no score/grade/rating — substance only).
    /// docs/phases/AI_Readiness.md §8
    static let buildAIReadiness = make(
        id: "code_ai_readiness", name: "AI Readiness", lane: .code,
        output: .aiReadinessReport, defaultEffort: .high,
        description: "Audit a repo for agent workability: setup, docs, tests, loop, automation, and shape. One report with three fixes, cold-read receipts, and what is already right.",
        rows: {
            // Loop scout prefers non-OpenCode seats (dogfood AB1CCB53: OpenCode
            // quota emptied the maintenance bucket while status stayed done).
            var rows = needRows([
                ("readiness_setup_scout", .answer),
                ("readiness_context_cartographer", .answer),
                ("readiness_measurement_auditor", .answer),
                ("readiness_test_infra_scout", .answer),
                ("readiness_loop_scout", .answer),
                ("readiness_automation_mapper", .answer),
                ("readiness_shape_specialist", .answer),
                ("readiness_strength_scout", .answer)
            ], tags: [.code])
            if let idx = rows.firstIndex(where: { $0.skillId == "readiness_loop_scout" }) {
                rows[idx] = row(
                    "readiness_loop_scout", .answer,
                    preferred: gptSol,
                    fallbacks: [sonnet, opus, cursorGrok, kimi, gemini],
                    fallback: .anyReady
                )
            }
            return rows
        }(),
        writer: "ai_readiness_writer", dissent: .compareOptions,
        mutating: false,
        typeTags: ["ai-readiness", "audit", "agent", "code-health", "setup"],
        starters: [
            "Audit this repo for AI readiness.",
            "How workable is this repo for an agent? Give me the three fixes that would help most."
        ])

    // MARK: - Unified run model teams

    /// Auto: the default route — one agent, mutating-allowed, no special-case code
    /// path. "Auto" because it picks your go-to agent and just runs it.
    static let defaultChat = make(
        id: "default_chat", name: "Auto", lane: .code, output: .plan, defaultEffort: .med,
        description: "The default route — your go-to agent in the repo, talk or build.",
        rows: [
            row(SkillCatalog.directChatSkillId, .answer, preferred: composer, fallback: .laneCapable)
        ],
        writer: SkillCatalog.directChatSkillId,
        lead: TeamLeadSpec(skillId: SkillCatalog.directChatSkillId, preferredModelId: composer, fallbackPolicy: .laneCapable),
        mutating: true, executionSourceId: "cursor_agent",
        typeTags: ["chat", "ask", "question"],
        starters: [])

    /// Build a Slice — the built-in execution preset (docs/operations/Execution-Playbook.md).
    /// Playbook text lives only on the `execution_playbook` skill template
    /// (`SkillCatalog.assemblePrompt`). Do not also put it in `starters` —
    /// `RunService` prepends `starterPrompts.first` for mutating teams, which
    /// would double-inject the same preamble (D1 / Pilot_Defect_Fixes).
    static let executionPlaybook = make(
        id: "build_slice", name: "Build a Slice", lane: .code, output: .plan, defaultEffort: .high,
        description: "Disciplined build loop: slice → narrow edits → proof → deslop → audit → commit.",
        rows: [
            row("execution_playbook", .answer, preferred: composer, fallback: .laneCapable)
        ],
        writer: "plan_writer_build",
        lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: composer, fallbackPolicy: .laneCapable),
        mutating: true, executionSourceId: "cursor_agent",
        typeTags: ["build", "implement", "ship", "slice", "execute"],
        starters: [])

    // MARK: - Design teams

    // Design seats are builder/reasoning roles (Team_Catalog_Normalization.md):
    // each seat builds a bounded renderable surface; the host capture step
    // screenshots that receipt for the board hero tile (docs/operations/Design_Lane.md).

    /// Design Min — the leanest credible design take: structure plus one visual
    /// system seat that builds and lands a screenshot receipt. Same writer/output
    /// as the family. Depth splits charters rather than deleting them
    /// (`docs/operations/Spec_Review.md` §Depth splits charters): the Default's
    /// `interaction_designer` job is absorbed as a second named pass on the visual
    /// seat, so a Min board still owes states and flow — not just a happy-path skin.
    static let designMin = make(
        id: "design_design_min", name: "Design Min", lane: .design, output: .designBoard, defaultEffort: .med,
        description: "Quick credible design take — the essential structure plus one rendered mockup that still owes its states and flow.",
        rows: [
            needRow("information_architect", .answer, tags: [.design]),
            needRow("design_min_visual_system", .answer, tags: [.design])
        ],
        writer: "design_board_writer", dissent: .compareOptions,
        typeTags: ["design-min"],
        starters: ["Give me one clean, credible design for <screen/flow> — fast."])

    static let designCore = make(
        id: "design_design", name: "Design", lane: .design, output: .designBoard, defaultEffort: .med, isDefault: true,
        description: "Design or redesign a screen or flow — credible interface options with the tradeoffs made visible.",
        rows: [
            needRow("information_architect", .answer, tags: [.design]),
            needRow("interaction_designer", .answer, tags: [.design]),
            needRow("visual_system_designer", .answer, tags: [.design])
        ],
        writer: "design_board_writer", dissent: .compareOptions,
        typeTags: ["design", "screen", "mockup", "ui", "interface", "directions"],
        starters: ["Design <screen/flow>: give me three credible interface directions with the tradeoffs made visible."])

    /// Design Max — the Default's job with widened divergence. Absorbs the folded
    /// Radical Directions team (founder-approved, Team_Catalog_Normalization.md):
    /// the Default's structure/interaction/visual seats plus the three divergence
    /// direction seats, so the board explores multiple genuinely different
    /// credible directions before converging. Same writer/output as the family.
    static let designMax = make(
        id: "design_design_max", name: "Design Max", lane: .design, output: .designBoard, defaultEffort: .high,
        description: "Design with widened divergence — credible interface options plus multiple genuinely different radical directions before the team converges.",
        rows: [
            needRow("information_architect", .answer, tags: [.design]),
            needRow("interaction_designer", .answer, tags: [.design]),
            needRow("visual_system_designer", .answer, tags: [.design]),
            // Divergence direction seats each build a surface and land a screenshot receipt.
            needRow("minimal_direction", .answer, tags: [.design]),
            needRow("bold_direction", .answer, tags: [.design]),
            needRow("editorial_direction", .answer, tags: [.design])
        ],
        writer: "design_board_writer", dissent: .compareOptions,
        typeTags: ["design-max", "divergent", "explore", "alternatives"],
        starters: ["Design <surface> with widened divergence: credible options plus genuinely different radical directions before we converge."])

    static let designPremiumPolish = make(
        id: "design_polish", name: "Polish", lane: .design, output: .polishBoard, defaultEffort: .high,
        description: "Make an existing surface feel expensive, intentional, and native — no semantic change.",
        rows: needRows([
            ("hierarchy_sculptor", .answer),
            ("type_spacing_auditor", .answer),
            ("polish_critic", .review)
        ], tags: [.design]),
        writer: "polish_board_writer",
        typeTags: ["polish", "premium", "native", "refine", "expensive", "calm"],
        starters: ["Give me two more polished versions of <screen> — calmer, more intentional, native."])

    static let designUsabilityTriage = make(
        id: "design_usability_review", name: "Usability Review", lane: .design, output: .polishBoard, defaultEffort: .med,
        description: "Diagnose why a surface feels confusing, slow, risky, or hard to repeat.",
        rows: needRows([
            ("journey_mapper", .answer),
            ("control_ergonomics", .answer),
            ("cognitive_load_cutter", .review)
        ], tags: [.design]),
        writer: "usability_triage_writer",
        typeTags: ["usability", "ux", "confusing", "friction", "diagnose"],
        starters: ["Why does <surface> feel confusing or slow? Find the friction and the smallest fixes."])

    // MARK: - Copy teams (parity; full type packs owned by docs/phases/copy)

    static let copyCore = make(
        id: "copy_core", name: "Copy Core", lane: .copy, output: .copyBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a copy prompt into clear, persuasive options grounded in the real offer.",
        rows: needRows([
            ("offer_strategist", .answer),
            ("headline_writer", .answer),
            ("direct_response_writer", .answer),
            ("objection_hunter", .answer),
            ("cta_writer", .answer),
            ("proof_skeptic", .review),
            ("brand_voice", .review)
        ], tags: [.copy]),
        writer: "copy_board_writer",
        typeTags: ["copy", "writing", "persuasive", "messaging", "tone"],
        starters: ["Write clearer, more persuasive options for <copy>."])

    static let copyLandingPage = make(
        id: "copy_landing", name: "Copy Landing", lane: .copy, output: .copyBoard, defaultEffort: .high,
        description: "Rewrite a landing page so the offer is clear, trusted, and converts.",
        rows: needRows([
            ("offer_strategist", .answer),
            ("headline_writer", .answer),
            ("cta_writer", .answer),
            ("direct_response_writer", .answer),
            ("objection_hunter", .answer),
            ("proof_skeptic", .review),
            ("brand_voice", .review)
        ], tags: [.copy]),
        writer: "landing_copy_writer",
        typeTags: ["landing-page", "landing", "marketing", "conversion", "page", "offer"],
        starters: ["Rewrite my landing page so the offer is clear, trusted, and converts."])

    // MARK: - Signal teams (the outside-world scout craft)

    static let signalPostToProject = make(
        id: "signal_outside", name: "Research", lane: .signal, output: .insight,
        defaultEffort: .med, isDefault: true,
        description: "Paste an X post, YouTube video, article, or release note and get what it actually means for THIS project — what happened, why it matters here, and what to do about it, with source receipts and a freshness check. One model fetches and distills the source (Grok reads X; `vvx` reads video transcripts), then several different models read that same distilled source independently, so you get a triangulated read instead of one model's opinion, plus a skeptic pass that argues against it.",
        scout: signalScoutGrok,
        rows: [
            TeamAgentSpec(id: "signal_interpret", skillId: "signal_interpret", purpose: .answer,
                           count: 3, triangulate: true, triangulatePreferenceIds: signalInterpreterPreference),
            row("signal_skeptic", .review, preferred: sonnet)
        ], writer: "insight_writer", dissent: .preserveDissent,
        typeTags: ["signal", "external", "news", "article", "apply", "insight"],
        starters: ["Paste an X post, video, or article link and ask how it applies to this project.",
                   "What does this release note mean for us?"])

    static let signalWhatToBuildNext = make(
        id: "signal_what_to_build_next", name: "What to Build Next", lane: .signal, output: .insight,
        defaultEffort: .high,
        description: "Scan what recently changed outside the repo and recommend the next build direction for this Project, with sourced reasoning, fit, and a skeptic pass.",
        rows: [
            row("signal_landscape_scanner", .answer, preferred: grok),
            row("signal_project_fit", .answer, preferred: gptSol),
            row("signal_product_ideas", .answer, preferred: gemini),
            row("signal_skeptic", .review, preferred: sonnet)
        ], writer: "insight_writer", dissent: .compareOptions,
        typeTags: ["roadmap", "next", "direction", "opportunity"],
        starters: ["What should we build next given what changed outside the repo this week?"])
}
