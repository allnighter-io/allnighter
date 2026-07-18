import Foundation

/// The built-in lane-scoped teams — product assets shipped with Allnighter
/// (Team_Catalog §Built-in Team Manifest Index). Built-in ids are an
/// immutable public contract once used in history/reproduce commands; built-ins
/// cannot be edited directly — users duplicate them to customize.
public enum BuiltInTeams {

    public static let all: [TeamPreset] = [
        buildCore, buildBugHunt, buildBugHuntMax, buildGUIBugHunt, buildSecurityReview,
        buildSpecReviewMin, buildSpecReview, buildSpecReviewMax, buildReleaseProof,
        buildGrowthMin, buildGrowth, buildGrowthMax,
        defaultChat, executionPlaybook,
        designCore, designPremiumPolish, designConversionStudio, designRadicalDirections, designUsabilityTriage,
        copyCore, copyLandingPage,
        signalPostToProject, signalWhatToBuildNext
    ]

    private static let byID: [String: TeamPreset] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func team(_ id: String) -> TeamPreset? { byID[id] }
    public static func teams(in lane: WorkLane) -> [TeamPreset] { all.teams(in: lane) }

    // MARK: - Model routing (fan-out diversity policy)

    /// Synthesis Lead — Fable 5 (flagship-only). ChatGPT 5.6 Sol is the strategic
    /// flagship worker seat. Antigravity Opus is never a preferred seed.
    private static let leadFlagship = "model_fable"
    private static let strategicFlagship = "model_chatgpt_sol"
    private static let opus = "model_opus"
    /// Default worker anchor for mutating Auto / Execution Playbook (Cursor).
    private static let composer = "model_cursor_composer_25"
    private static let chatgpt = "model_chatgpt"
    private static let gemini = "model_gemini"
    private static let sonnet = "model_sonnet"
    private static let kimi = "model_kimi_k3"
    private static let cursorGrok = "model_cursor_grok_45"
    private static let cursorAuto = "model_cursor_auto"
    private static let agyOpus = "model_agy_opus"
    /// External / X / web research scout (also high/mid value in rotations).
    private static let grok = "model_grok"

    /// Distinct high + high/mid seats once each — Composer at most once.
    private static let codeWorkerRotation: [String] = [
        cursorGrok, kimi, grok, chatgpt, composer, gemini, sonnet
    ]
    private static let designWorkerRotation: [String] = [
        gemini, chatgpt, cursorGrok
    ]
    /// Image mockup seats — one finished image per worker; only these three engines generate images.
    private static let designImageModels: [String] = [gemini, chatgpt, grok]

    private static func designMockupRows(_ specs: [(String, TeamWorkerPurpose)]) -> [TeamWorkerSpec] {
        specs.enumerated().map { offset, spec in
            row(spec.0, spec.1,
                preferred: designImageModels[offset % designImageModels.count],
                tags: [.image])
        }
    }
    private static let copyWorkerRotation: [String] = [
        chatgpt, sonnet, kimi, cursorGrok, composer, gemini, grok
    ]

    /// Growth Panel preference — ONE shared growth-hacker prompt spread across
    /// DISTINCT models (triangulation), front-loaded by strength + lab diversity so
    /// even a small `count` spans different labs. `count` is a cap: the row degrades
    /// below it, dropping seats rather than double-booking or requiring any one
    /// model. Never benches the best (a flagship is picked when ready), never fails
    /// (Fable is reserved for the Lead; ≥1 ready model still runs).
    private static let growthPreference: [String] = [
        opus, strategicFlagship, grok, gemini, kimi, sonnet, chatgpt, composer, cursorGrok
    ]

    // MARK: - Builders

    /// One worker row. Row id defaults to the skill id (unique within a team).
    private static func row(
        _ skillId: String, _ purpose: TeamWorkerPurpose,
        preferred: String? = nil, required: Bool = true,
        fallbacks: [String] = [],
        tags: [ModelCapabilityTag] = [], fallback: ModelFallbackPolicy = .anyReady
    ) -> TeamWorkerSpec {
        TeamWorkerSpec(id: skillId, skillId: skillId, purpose: purpose,
                       preferredModelId: preferred,
                       fallbackModelIds: fallbacks.isEmpty ? nil : fallbacks,
                       requiredCapabilityTags: tags,
                       fallbackPolicy: fallback, required: required)
    }

    /// Complete built-in fallback coverage for answer teams. Role-specific
    /// priorities come first; remaining built-ins keep a team runnable on a
    /// different installed CLI. Unknown/custom models remain available through
    /// the row's broad fallback policy after this list is exhausted.
    private static func workerFallbacks(
        preferred: String,
        priorities: [String]
    ) -> [String] {
        let broad = [
            kimi, cursorGrok, grok, strategicFlagship, opus, chatgpt,
            leadFlagship, composer, gemini, sonnet, cursorAuto, agyOpus
        ]
        var seen = Set([preferred])
        return (priorities + broad).filter { seen.insert($0).inserted }
    }

    private static func specRow(
        _ skillId: String,
        _ purpose: TeamWorkerPurpose,
        preferred: String,
        priorities: [String]
    ) -> TeamWorkerSpec {
        row(skillId, purpose, preferred: preferred,
            fallbacks: workerFallbacks(preferred: preferred, priorities: priorities))
    }

    /// Spread workers across distinct models — the point of fan-out.
    /// `strategicSeats` pins high-judgment roles to ChatGPT 5.6 Sol so the crew
    /// gets flagship reasoning, not only Fable synthesis.
    private static func diverseRows(
        _ specs: [(String, TeamWorkerPurpose)],
        rotation: [String],
        startIndex: Int = 0,
        strategicSeats: Set<String> = []
    ) -> [TeamWorkerSpec] {
        specs.enumerated().map { offset, spec in
            let preferred = strategicSeats.contains(spec.0)
                ? strategicFlagship
                : rotation[(startIndex + offset) % rotation.count]
            return row(spec.0, spec.1, preferred: preferred)
        }
    }

    /// Fable synthesizes; when Fable is unavailable, **ChatGPT 5.6 Sol is the
    /// designated deputy lead for EVERY team** (the standard). Codex route first
    /// (`model_chatgpt` — how Sol is accessed here), then the Cursor route
    /// (`model_chatgpt_sol`), then the rest. `.strongestReady` already prefers Sol
    /// (rank 99, above every non-Fable model) — pinning both Sol routes as the top
    /// two fallbacks makes the standard explicit and independent of policy/rank drift.
    private static func synthesisLead(_ writer: String, dissent: DissentPolicy = .preserveDissent) -> TeamLeadSpec {
        TeamLeadSpec(
            skillId: writer,
            preferredModelId: leadFlagship,
            fallbackModelIds: [
                chatgpt, strategicFlagship, opus, kimi, cursorGrok, grok,
                composer, sonnet, gemini, cursorAuto, agyOpus
            ],
            fallbackPolicy: .strongestReady,
            dissentPolicy: dissent)
    }

    /// Every built-in carries one mandatory Team Lead (synthesizer). Effort scales
    /// the crew, never the Lead.
    private static func make(
        id: String, name: String, lane: WorkLane, output: TeamOutputKind,
        defaultEffort: EffortLevel, isDefault: Bool = false, description: String,
        scout: TeamWorkerSpec? = nil,
        rows: [TeamWorkerSpec], writer: String, dissent: DissentPolicy = .preserveDissent,
        lead: TeamLeadSpec? = nil,
        mutating: Bool = false, executionSourceId: String? = nil,
        typeTags: [String] = [], starters: [String] = []
    ) -> TeamPreset {
        TeamPreset(
            id: id, displayName: name, lane: lane, description: description, outputKind: output,
            mutating: mutating,
            executionSourceId: executionSourceId,
            defaultEffort: defaultEffort, isDefaultForLane: isDefault, scout: scout, workerSpecs: rows,
            lead: lead ?? synthesisLead(writer, dissent: dissent),
            typeTags: typeTags, starterPrompts: starters, builtIn: true, version: 1)
    }

    /// The Signal scout row: Grok reads / researches X and public web sources first.
    static let signalScoutGrok = TeamWorkerSpec(
        id: "signal_source_reader", skillId: "signal_source_reader", purpose: .answer,
        preferredModelId: grok, fallbackPolicy: .laneCapable)

    /// Canonical interpreter preference: Grok (web-aware), ChatGPT 5.6, then Gemini.
    static let signalInterpreterPreference = [grok, chatgpt, gemini]

    // MARK: - Code teams

    static let buildCore = make(
        id: "code_core", name: "Code Core", lane: .code, output: .plan, defaultEffort: .med, isDefault: true,
        description: "Turn a rough product/build prompt into an implementable plan with scope, architecture, risks, and proof.",
        rows: diverseRows([
            ("product_architect", .answer),
            ("proof_planner", .answer),
            ("first_principles_builder", .answer),
            ("code_maintainer", .answer),
            ("scope_steward", .review),
            ("security_privacy_reviewer", .review),
            ("contrarian_reviewer", .review)
        ], rotation: codeWorkerRotation, strategicSeats: ["first_principles_builder"]),
        writer: "plan_writer_build",
        starters: ["Turn this rough idea into an implementable plan with scope and proof.",
                   "Plan the smallest correct slice for <feature>."])

    /// Bug Hunt — bare/default depth tier. Lean 4-seat roster; two-judge A/B
    /// proved it ties the heavier roster on deliverable quality at lower seat
    /// cost, so it is the everyday choice (Team_Depth_Naming).
    static let buildBugHunt = make(
        id: "code_bug_hunt", name: "Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Find the real cause of a bug and plan the smallest correct fix: reproduce, name the truth owner, fix at the right level, prove it.",
        rows: diverseRows([
            ("bug_reproducer", .answer),
            ("truth_owner_mapper", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer)
        ], rotation: codeWorkerRotation),
        writer: "bug_packet_writer",
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
        rows: diverseRows([
            ("bug_reproducer", .answer),
            ("truth_owner_mapper", .answer),
            ("trace_mapper", .answer),
            ("state_skeptic", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer),
            ("contrarian_root_cause", .review),
            ("fix_altitude_reviewer", .review)
        ], rotation: codeWorkerRotation, strategicSeats: ["contrarian_root_cause"]),
        writer: "bug_packet_writer",
        starters: ["This bug has resisted earlier fixes — find the real cause and the right-level fix for <broken behavior>."])

    static let buildGUIBugHunt = make(
        id: "code_gui_bug_hunt", name: "GUI Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Fix visible native-app breakage with rendered proof, layout-watcher review, and the right truth owner.",
        rows: diverseRows([
            ("gui_bug_reproducer", .answer),
            ("gui_proof_guard", .answer),
            ("correct_fix_planner", .answer),
            ("regression_guard", .answer),
            ("truth_owner_mapper", .answer),
            ("state_skeptic", .answer),
            ("change_impact_reviewer", .answer),
            ("gui_layout_reviewer", .review),
            ("contrarian_root_cause", .review)
        ], rotation: codeWorkerRotation, startIndex: 2, strategicSeats: ["contrarian_root_cause"]),
        writer: "gui_bug_packet_writer")

    static let buildSecurityReview = make(
        id: "code_security_review", name: "Security Review", lane: .code, output: .securityRegister, defaultEffort: .high,
        description: "Evaluate privacy, credentials, permissions, exposure, and destructive operations with small-team shipping judgment.",
        rows: diverseRows([
            ("boundary_mapper", .answer),
            ("secrets_reviewer", .answer),
            ("permission_reviewer", .answer),
            ("data_flow_reviewer", .answer),
            ("abuse_case_reviewer", .answer),
            ("dependency_injection_reviewer", .review),
            ("security_fix_prioritizer", .review)
        ], rotation: codeWorkerRotation, strategicSeats: ["security_fix_prioritizer"]),
        writer: "security_register_writer", dissent: .riskRegister)

    // MARK: - Growth (same prompt, diverse models)

    /// Growth Min — three diverse models, no Claude/ChatGPT subscription required.
    static let buildGrowthMin = make(
        id: "code_growth_min", name: "Growth Min", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Fast growth read: up to 4 diverse models (a flagship when you have one) hunt the wedge that makes X builders love it — kept simple and on-core. Runs on whatever's ready; drops a seat rather than doubling up.",
        rows: [
            TeamWorkerSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           count: 4, triangulate: true, triangulatePreferenceIds: growthPreference)
        ],
        writer: "growth_writer",
        typeTags: ["growth", "min"],
        starters: [
            "Growth: how do we make X builders LOVE this and spread it, kept simple and on-core? Find the wedge, the shareable artifact, and the simplest lovable version."]
    )

    /// Growth — the everyday default. Four genuinely different frontier models
    /// on ONE shared growth-hacker prompt (the diversity is the model, not the lens);
    /// a first-principles synthesizer that hunts the BEST idea — outlier or consensus —
    /// and never rewards agreement for its own sake.
    static let buildGrowth = make(
        id: "code_growth", name: "Growth", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Make X builders and influencers LOVE a feature: up to 6 diverse models — flagships recruited as workers when ready (never benched for the Lead) — swing big on the same growth question; Fable synthesizes and picks the highest-leverage wedge that stays on-core and simple, valuing the breakout outlier over safe consensus. Runs on whatever's ready; drops a seat rather than doubling up.",
        rows: [
            TeamWorkerSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           count: 6, triangulate: true, triangulatePreferenceIds: growthPreference)
        ],
        writer: "growth_writer",
        typeTags: ["growth"],
        starters: [
            "Growth: how do we make the X builders and influencers who matter LOVE this — enough to use it daily and tell others — while keeping it simple and true to the core? Find the wedge, the aha, the shareable artifact, and what to cut.",
            "Review docs/phases/<Feature>.md with Growth: the loved wedge, the viral loop, the simplest lovable version, and the breakout bet."]
    )

    /// Growth Max — the four-model roster plus an X/web research scout that reads
    /// what is actually spreading in the category right now, so the ideas are grounded
    /// in live signal, not vibes.
    static let buildGrowthMax = make(
        id: "code_growth_max", name: "Growth Max", lane: .code,
        output: .plan, defaultEffort: .high,
        description: "Deep growth read: an X/web signal scout on what is spreading now, then up to 8 diverse models on the wedge — every flagship and idle model recruited when ready (Sol, ChatGPT 5.6, Opus, Sonnet, Composer…) — and a synthesizer that prizes the breakout outlier over safe consensus. Drops a seat rather than doubling up.",
        scout: specRow("signal_source_reader", .answer, preferred: grok,
                       priorities: [cursorGrok, kimi, gemini, chatgpt]),
        rows: [
            TeamWorkerSpec(id: "growth_seats", skillId: "growth_hacker", purpose: .answer,
                           count: 8, triangulate: true, triangulatePreferenceIds: growthPreference)
        ],
        writer: "growth_writer",
        typeTags: ["growth", "max"],
        starters: [
            "Growth Max: scout what is spreading in the category on X now, then find the wedge that makes builders LOVE this and the shareable viral loop — kept simple and on-core."]
    )

    /// Spec Review Min — the smallest useful cross-CLI panel. Its three workers
    /// prefer Kimi, Cursor, and Grok, so no Claude/Codex subscription is required.
    static let buildSpecReviewMin = make(
        id: "code_spec_review_min", name: "Spec Review Min", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "A lean spec check with first-principles, proof, and scope coverage. Built to stay useful without Claude or ChatGPT.",
        rows: [
            specRow(
                "spec_first_principles_reviewer", .answer, preferred: kimi,
                priorities: [cursorGrok, grok, strategicFlagship, opus, chatgpt, leadFlagship, composer, gemini, sonnet]),
            specRow(
                "spec_proof_planner", .answer, preferred: cursorGrok,
                priorities: [grok, kimi, composer, chatgpt, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_scope_steward", .answer, preferred: grok,
                priorities: [kimi, cursorGrok, gemini, composer, chatgpt, strategicFlagship, opus, leadFlagship, sonnet])
        ],
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["spec-review", "min"],
        starters: [
            "Run a lean Spec Review: challenge the premise, cut scope, and make the proof concrete. Review only — do not edit the doc."]
    )

    /// Spec Review — the everyday default. Five independent lenses span Cursor,
    /// Kimi, Grok, and Antigravity before any fallback is needed.
    static let buildSpecReview = make(
        id: "code_spec_review", name: "Spec Review", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "Harden a feature or phase spec before you build: challenge the premise, audit the contract, make proof concrete, and reject noise — review only.",
        rows: [
            specRow(
                "spec_first_principles_reviewer", .answer, preferred: strategicFlagship,
                priorities: [opus, leadFlagship, kimi, cursorGrok, grok, chatgpt, composer, gemini, sonnet]),
            specRow(
                "spec_doc_hygiene_reviewer", .answer, preferred: kimi,
                priorities: [cursorGrok, grok, composer, chatgpt, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_contract_auditor", .answer, preferred: grok,
                priorities: [cursorGrok, kimi, chatgpt, composer, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_proof_planner", .answer, preferred: cursorGrok,
                priorities: [grok, kimi, composer, chatgpt, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_contrarian_reviewer", .review, preferred: gemini,
                priorities: [grok, kimi, cursorGrok, composer, chatgpt, strategicFlagship, opus, leadFlagship, sonnet])
        ],
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["spec-review"],
        starters: [
            "Review this spec. Be brief. Find the highest-leverage changes, concrete contract gaps, and explicit rejects. Review only — do not edit the doc.",
            "Harden docs/phases/<Spec>.md: premise, agent routing, contract, proof, and what to cut."]
    )

    /// Spec Review Max — the full launch/hard-case panel. The current full roster
    /// moved here; each lens gets its own preferred model and broad cross-CLI chain.
    static let buildSpecReviewMax = make(
        id: "code_spec_review_max", name: "Spec Review Max", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "Full-depth review for launch and hard specs: outside research plus seven blind lenses spanning premise, operations, contract, proof, scope, simplicity, and a rival approach.",
        scout: specRow(
            "spec_outside_scout", .answer, preferred: grok,
            priorities: [cursorGrok, kimi, strategicFlagship, chatgpt, opus, leadFlagship, gemini, composer, sonnet]),
        rows: [
            specRow(
                "spec_first_principles_reviewer", .answer, preferred: strategicFlagship,
                priorities: [opus, leadFlagship, kimi, cursorGrok, grok, chatgpt, composer, gemini, sonnet]),
            specRow(
                "spec_doc_hygiene_reviewer", .answer, preferred: kimi,
                priorities: [cursorGrok, grok, composer, chatgpt, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_contract_auditor", .answer, preferred: cursorGrok,
                priorities: [grok, kimi, chatgpt, composer, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_proof_planner", .answer, preferred: chatgpt,
                priorities: [cursorGrok, kimi, grok, composer, strategicFlagship, opus, leadFlagship, gemini, sonnet]),
            specRow(
                "spec_scope_steward", .answer, preferred: grok,
                priorities: [kimi, cursorGrok, gemini, composer, chatgpt, strategicFlagship, opus, leadFlagship, sonnet]),
            specRow(
                "spec_hype_skeptic", .review, preferred: composer,
                priorities: [grok, kimi, cursorGrok, gemini, chatgpt, strategicFlagship, opus, leadFlagship, sonnet]),
            specRow(
                "spec_contrarian_reviewer", .review, preferred: gemini,
                priorities: [grok, kimi, cursorGrok, composer, chatgpt, strategicFlagship, opus, leadFlagship, sonnet])
        ],
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["launch", "spec-review", "max"],
        starters: [
            "Run Spec Review Max on this launch or hard-case spec. Find ranked gems and explicit rejects; review only — do not edit the doc.",
            "Harden docs/phases/<Spec>.md at full depth: outside signal, premise, contract, proof, scope, simplicity, and a rival approach."]
    )

    static let buildReleaseProof = make(
        id: "code_release_proof", name: "Release Proof", lane: .code, output: .proofPacket, defaultEffort: .high,
        description: "Before a slice closes, prove that the owner-visible claim is actually true.",
        rows: diverseRows([
            ("acceptance_auditor", .answer),
            ("test_runner_planner", .answer),
            ("risk_register", .review),
            ("edge_case_hunter", .answer),
            ("contract_drift_checker", .answer),
            ("demo_narrator", .review)
        ], rotation: codeWorkerRotation, startIndex: 3, strategicSeats: ["acceptance_auditor"]),
        writer: "proof_packet_writer", dissent: .riskRegister,
        starters: ["Prove this slice is actually done before I believe it."])

    // MARK: - Unified run model teams

    /// Auto: the default route — one agent, mutating-allowed, no special-case code
    /// path. "Auto" because it picks your go-to agent and just runs it.
    static let defaultChat = make(
        id: "default_chat", name: "Auto", lane: .code, output: .plan, defaultEffort: .med,
        description: "The default route — your go-to agent in the repo, talk or build.",
        rows: [
            row(SkillCatalog.directChatSkillId, .answer, preferred: composer, fallback: .sameSource)
        ],
        writer: SkillCatalog.directChatSkillId,
        lead: TeamLeadSpec(skillId: SkillCatalog.directChatSkillId, preferredModelId: composer, fallbackPolicy: .sameSource),
        mutating: true, executionSourceId: "cursor_agent",
        starters: [])

    /// Execution Playbook as a built-in execution preset (docs/operations/Execution-Playbook.md).
    /// Playbook text lives only on the `execution_playbook` skill template
    /// (`SkillCatalog.assemblePrompt`). Do not also put it in `starters` —
    /// `RunService` prepends `starterPrompts.first` for mutating teams, which
    /// would double-inject the same preamble (D1 / Pilot_Defect_Fixes).
    static let executionPlaybook = make(
        id: "execution_playbook", name: "Execution Playbook", lane: .code, output: .plan, defaultEffort: .high,
        description: "Disciplined senior-engineer loop: slice → narrow edits → proof → deslop → audit → commit.",
        rows: [
            row("execution_playbook", .answer, preferred: composer, fallback: .sameSource)
        ],
        writer: "plan_writer_build",
        lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: composer, fallbackPolicy: .sameSource),
        mutating: true, executionSourceId: "cursor_agent",
        starters: [])

    // MARK: - Design teams

    static let designCore = make(
        id: "design_core", name: "Design Core", lane: .design, output: .designBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a product/design prompt into three credible interface mockups, then make the tradeoffs visible.",
        rows: designMockupRows([
            ("information_architect", .answer),
            ("interaction_designer", .answer),
            ("visual_system_designer", .answer),
        ]),
        writer: "design_board_writer", dissent: .compareOptions)

    static let designPremiumPolish = make(
        id: "design_premium_polish", name: "Premium Polish", lane: .design, output: .polishBoard, defaultEffort: .high,
        description: "Make an existing surface feel expensive, intentional, and native without changing its product semantics.",
        rows: diverseRows([
            ("hierarchy_sculptor", .answer),
            ("type_spacing_auditor", .answer),
            ("polish_critic", .review)
        ], rotation: designWorkerRotation),
        writer: "polish_board_writer",
        starters: ["Give me two more polished versions of <screen> — calmer, more intentional, native."])

    static let designConversionStudio = make(
        id: "design_conversion_studio", name: "Conversion Studio", lane: .design, output: .designBoard, defaultEffort: .high,
        description: "Improve a product/marketing surface so users understand the offer, trust it, and know what to do next.",
        rows: designMockupRows([
            ("offer_clarity", .answer),
            ("cta_path", .answer),
            ("trust_builder", .answer),
        ]),
        writer: "conversion_board_writer")

    static let designRadicalDirections = make(
        id: "design_radical_directions", name: "Radical Directions", lane: .design, output: .designBoard, defaultEffort: .med,
        description: "Generate three genuinely different design directions before the team converges too early.",
        rows: designMockupRows([
            ("minimal_direction", .answer),
            ("bold_direction", .answer),
            ("editorial_direction", .answer),
        ]),
        writer: "direction_board_writer", dissent: .compareOptions)

    static let designUsabilityTriage = make(
        id: "design_usability_triage", name: "Usability Triage", lane: .design, output: .polishBoard, defaultEffort: .med,
        description: "Find why a surface feels confusing, slow, risky, or hard to repeat.",
        rows: diverseRows([
            ("journey_mapper", .answer),
            ("control_ergonomics", .answer),
            ("cognitive_load_cutter", .review)
        ], rotation: designWorkerRotation, startIndex: 1),
        writer: "usability_triage_writer")

    // MARK: - Copy teams (parity; full type packs owned by docs/phases/copy)

    static let copyCore = make(
        id: "copy_core", name: "Copy Core", lane: .copy, output: .copyBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a copy prompt into clear, persuasive options grounded in the real offer.",
        rows: diverseRows([
            ("offer_strategist", .answer),
            ("headline_writer", .answer),
            ("direct_response_writer", .answer),
            ("objection_hunter", .answer),
            ("cta_writer", .answer),
            ("proof_skeptic", .review),
            ("brand_voice", .review)
        ], rotation: copyWorkerRotation),
        writer: "copy_board_writer",
        starters: ["Write clearer, more persuasive options for <copy>."])

    static let copyLandingPage = make(
        id: "copy_landing_page", name: "Landing Page Team", lane: .copy, output: .copyBoard, defaultEffort: .high,
        description: "Rewrite a landing page so the offer is clear, trusted, and converts.",
        rows: diverseRows([
            ("offer_strategist", .answer),
            ("headline_writer", .answer),
            ("cta_writer", .answer),
            ("direct_response_writer", .answer),
            ("objection_hunter", .answer),
            ("proof_skeptic", .review),
            ("brand_voice", .review)
        ], rotation: copyWorkerRotation, startIndex: 2),
        writer: "landing_copy_writer", typeTags: ["landing-page"])

    // MARK: - Signal teams (the outside-world scout craft)

    static let signalPostToProject = make(
        id: "signal_post_to_project", name: "Post-to-Project Signal", lane: .signal, output: .insight,
        defaultEffort: .med, isDefault: true,
        description: "Grok grabs and distills a public X post, thread, article, or release note, then several different models reason over it (triangulation) into a Project-aware Insight: what happened, why it matters here, with source receipts, freshness, and a skeptic pass.",
        scout: signalScoutGrok,
        rows: [
            TeamWorkerSpec(id: "signal_interpret", skillId: "signal_interpret", purpose: .answer,
                           count: 3, triangulate: true, triangulatePreferenceIds: signalInterpreterPreference),
            row("signal_skeptic", .review, preferred: sonnet)
        ], writer: "insight_writer", dissent: .preserveDissent,
        starters: ["Paste a public X post or article link and ask how it applies to this project.",
                   "What does this release note mean for us?"])

    static let signalWhatToBuildNext = make(
        id: "signal_what_to_build_next", name: "What should we build next?", lane: .signal, output: .insight,
        defaultEffort: .high,
        description: "Scan what recently changed outside the repo and recommend the next build direction for this Project, with sourced reasoning, fit, and a skeptic pass.",
        rows: [
            row("signal_landscape_scanner", .answer, preferred: grok),
            row("signal_project_fit", .answer, preferred: chatgpt),
            row("signal_product_ideas", .answer, preferred: gemini),
            row("signal_skeptic", .review, preferred: sonnet)
        ], writer: "insight_writer", dissent: .compareOptions,
        starters: ["What should we build next given what changed outside the repo this week?"])
}
