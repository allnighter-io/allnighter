import Foundation

/// The built-in lane-scoped teams — product assets shipped with Allnighter
/// (Team_Catalog §Built-in Team Manifest Index). Built-in ids are an
/// immutable public contract once used in history/reproduce commands; built-ins
/// cannot be edited directly — users duplicate them to customize.
public enum BuiltInTeams {

    public static let all: [TeamPreset] = [
        buildCore, buildBugHunt, buildBugHuntMax, buildGUIBugHunt, buildSecurityReview, buildSpecReview, buildReleaseProof,
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

    /// Synthesis Lead — Claude Code Opus 4.8. Antigravity Opus 4.6 (`model_agy_opus`)
    /// is never a preferred seed; it is fallback-only via Flagship tier order /
    /// strongestReady ranking when Claude Code is unavailable.
    private static let leadOpus = "model_opus"
    /// Default worker anchor for code/build teams (how users actually run teams).
    private static let composer = "model_cursor_composer_25"
    private static let chatgpt = "model_chatgpt"
    private static let gemini = "model_gemini"
    private static let sonnet = "model_sonnet"
    /// External / X / web research scout.
    private static let grok = "model_grok"

    /// Composer-heavy rotation, but never one model for the whole crew when depth exists.
    private static let codeWorkerRotation: [String] = [
        composer, chatgpt, gemini, composer, sonnet, chatgpt, gemini, composer, sonnet
    ]
    private static let designWorkerRotation: [String] = [
        gemini, chatgpt, grok
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
        chatgpt, composer, sonnet, chatgpt, composer, gemini, chatgpt
    ]

    // MARK: - Builders

    /// One worker row. Row id defaults to the skill id (unique within a team).
    private static func row(
        _ skillId: String, _ purpose: TeamWorkerPurpose,
        preferred: String? = nil, required: Bool = true,
        tags: [ModelCapabilityTag] = [], fallback: ModelFallbackPolicy = .anyReady
    ) -> TeamWorkerSpec {
        TeamWorkerSpec(id: skillId, skillId: skillId, purpose: purpose,
                       preferredModelId: preferred, requiredCapabilityTags: tags,
                       fallbackPolicy: fallback, required: required)
    }

    /// Spread workers across distinct models — the point of fan-out.
    /// `strategicOpus` pins one high-judgment role to Opus so the crew gets
    /// flagship reasoning, not only flagship synthesis. Lab runs prove whether
    /// that slot earns its quota vs lead-only Opus.
    private static func diverseRows(
        _ specs: [(String, TeamWorkerPurpose)],
        rotation: [String],
        startIndex: Int = 0,
        strategicOpus: Set<String> = []
    ) -> [TeamWorkerSpec] {
        specs.enumerated().map { offset, spec in
            let preferred = strategicOpus.contains(spec.0)
                ? leadOpus
                : rotation[(startIndex + offset) % rotation.count]
            return row(spec.0, spec.1, preferred: preferred)
        }
    }

    /// Opus synthesizes; workers fan out across cheaper/different models.
    private static func synthesisLead(_ writer: String, dissent: DissentPolicy = .preserveDissent) -> TeamLeadSpec {
        TeamLeadSpec(skillId: writer, preferredModelId: leadOpus, fallbackPolicy: .strongestReady, dissentPolicy: dissent)
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

    /// Canonical interpreter preference: Grok (web-aware), GPT-5.5, then Gemini.
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
        ], rotation: codeWorkerRotation, strategicOpus: ["first_principles_builder"]),
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
        ], rotation: codeWorkerRotation, strategicOpus: ["contrarian_root_cause"]),
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
        ], rotation: codeWorkerRotation, startIndex: 2, strategicOpus: ["contrarian_root_cause"]),
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
        ], rotation: codeWorkerRotation, strategicOpus: ["security_fix_prioritizer"]),
        writer: "security_register_writer", dissent: .riskRegister)

    /// Spec Review — launch-tier spec hardening. Fan-out covers product/moat,
    /// contracts, proof, scope, doc hygiene (agent routing), and simplicity.
    /// Synthesizer returns a gem table + explicit rejects; review only.
    static let buildSpecReview = make(
        id: "code_spec_review", name: "Spec Review", lane: .code,
        output: .specReview, defaultEffort: .high,
        description: "Harden a feature or phase spec before you build: find the gems, name the risks, reject noise, and verify agent routing — review only, no doc edits.",
        scout: row("spec_outside_scout", .answer, preferred: grok),
        rows: diverseRows([
            ("spec_first_principles_reviewer", .answer),
            ("spec_doc_hygiene_reviewer", .answer),
            ("spec_contract_auditor", .answer),
            ("spec_proof_planner", .answer),
            ("spec_scope_steward", .answer),
            ("spec_hype_skeptic", .review),
            ("spec_contrarian_reviewer", .review)
        ], rotation: codeWorkerRotation, startIndex: 1, strategicOpus: ["spec_first_principles_reviewer"]),
        writer: "spec_review_writer", dissent: .compareOptions,
        typeTags: ["launch", "spec-review"],
        starters: [
            "Review this spec. Be brief. Find the highest-leverage gems to make it best-in-market. Review only — do not edit the doc.",
            "Harden docs/phases/<Spec>.md: moat, closed loop, proof, and what to cut. List explicit rejects (flashy UI, scope creep)."]
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
        ], rotation: codeWorkerRotation, startIndex: 3, strategicOpus: ["acceptance_auditor"]),
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
