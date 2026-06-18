import Foundation

/// The built-in lane-scoped teams — product assets shipped with Allnighter
/// (Fanout_Team_Catalog §Built-in Team Manifest Index). Built-in ids are an
/// immutable public contract once used in history/reproduce commands; built-ins
/// cannot be edited directly — users duplicate them to customize.
public enum BuiltInTeams {

    public static let all: [TeamPreset] = [
        buildCore, buildBugHunt, buildGUIBugHunt, buildSecurityReview, buildArchitecturePressureTest, buildReleaseProof,
        designCore, designPremiumPolish, designConversionStudio, designRadicalDirections, designUsabilityTriage,
        copyCore, copyLandingPage
    ]

    private static let byID: [String: TeamPreset] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func team(_ id: String) -> TeamPreset? { byID[id] }
    public static func teams(in lane: WorkLane) -> [TeamPreset] { all.teams(in: lane) }

    // MARK: - Builders

    /// One worker row. Row id defaults to the skill id (unique within a team).
    private static func row(
        _ skillId: String, _ purpose: TeamWorkerPurpose, _ minEffort: EffortLevel,
        preferred: String? = nil, required: Bool = true,
        tags: [ModelCapabilityTag] = [], fallback: ModelFallbackPolicy = .strongestReady
    ) -> TeamWorkerSpec {
        TeamWorkerSpec(id: skillId, skillId: skillId, purpose: purpose, minEffort: minEffort,
                       preferredModelId: preferred, requiredCapabilityTags: tags,
                       fallbackPolicy: fallback, required: required)
    }

    /// Every built-in carries one mandatory Team Lead (synthesizer) — strongest
    /// ready model by default (no hard capability requirement, so one ready CLI can
    /// still report back). Effort scales the crew, never the Lead.
    private static func make(
        id: String, name: String, lane: WorkLane, output: TeamOutputKind,
        defaultEffort: EffortLevel, isDefault: Bool = false, description: String,
        rows: [TeamWorkerSpec], writer: String, dissent: DissentPolicy = .preserveDissent,
        typeTags: [String] = []
    ) -> TeamPreset {
        TeamPreset(
            id: id, displayName: name, lane: lane, description: description, outputKind: output,
            defaultEffort: defaultEffort, isDefaultForLane: isDefault, workerSpecs: rows,
            effortPolicy: TeamEffortPolicy(defaultEffort: defaultEffort),
            lead: TeamLeadSpec(skillId: writer, fallbackPolicy: .strongestReady, dissentPolicy: dissent),
            typeTags: typeTags, builtIn: true, version: 1)
    }

    // MARK: - Build teams

    static let buildCore = make(
        id: "code_core", name: "Build Core", lane: .code, output: .plan, defaultEffort: .med, isDefault: true,
        description: "Turn a rough product/build prompt into an implementable plan with scope, architecture, risks, and proof.",
        rows: [
            row("product_architect", .answer, .low),
            row("proof_planner", .answer, .low),
            row("first_principles_builder", .answer, .med),
            row("code_maintainer", .answer, .med),
            row("scope_steward", .review, .med),
            row("security_privacy_reviewer", .review, .high),
            row("contrarian_reviewer", .review, .high)
        ], writer: "plan_writer_build")

    static let buildBugHunt = make(
        id: "code_bug_hunt", name: "Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Find the real cause of broken behavior, map the blast radius, and plan the smallest correct fix.",
        rows: [
            row("bug_reproducer", .answer, .low),
            row("truth_owner_mapper", .answer, .low),
            row("correct_fix_planner", .answer, .low),
            row("regression_guard", .answer, .low, preferred: "model_chatgpt", fallback: .anyReady),
            row("trace_mapper", .answer, .med),
            row("state_skeptic", .answer, .med),
            row("change_impact_reviewer", .answer, .med),
            row("user_impact_narrator", .review, .high),
            row("contrarian_root_cause", .review, .high)
        ], writer: "bug_packet_writer")

    static let buildGUIBugHunt = make(
        id: "code_gui_bug_hunt", name: "GUI Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Fix visible native-app breakage with rendered proof, layout-watcher review, and the right truth owner.",
        rows: [
            row("gui_bug_reproducer", .answer, .low),
            row("gui_proof_guard", .answer, .low),
            row("correct_fix_planner", .answer, .low),
            row("regression_guard", .answer, .low, preferred: "model_chatgpt", fallback: .anyReady),
            row("truth_owner_mapper", .answer, .med),
            row("state_skeptic", .answer, .med),
            row("change_impact_reviewer", .answer, .med),
            row("gui_layout_reviewer", .review, .high),
            row("contrarian_root_cause", .review, .high)
        ], writer: "gui_bug_packet_writer")

    static let buildSecurityReview = make(
        id: "code_security_review", name: "Security Review", lane: .code, output: .securityRegister, defaultEffort: .high,
        description: "Evaluate privacy, credentials, permissions, exposure, and destructive operations with small-team shipping judgment.",
        rows: [
            row("boundary_mapper", .answer, .low),
            row("secrets_reviewer", .answer, .low),
            row("permission_reviewer", .answer, .low),
            row("data_flow_reviewer", .answer, .med),
            row("abuse_case_reviewer", .answer, .med),
            row("dependency_injection_reviewer", .review, .high),
            row("security_fix_prioritizer", .review, .high)
        ], writer: "security_register_writer", dissent: .riskRegister)

    static let buildArchitecturePressureTest = make(
        id: "code_architecture_pressure_test", name: "Architecture Pressure Test", lane: .code,
        output: .architectureVerdict, defaultEffort: .med,
        description: "Pressure-test a proposed architecture before implementation hardens the wrong truth owner.",
        rows: [
            row("truth_owner", .answer, .low),
            row("boundary_mapper", .answer, .low),
            row("complexity_cutter", .answer, .low),
            row("failure_concurrency", .answer, .med),
            row("migration_steward", .answer, .med),
            row("contrarian_architect", .review, .high)
        ], writer: "architecture_verdict_writer", dissent: .compareOptions)

    static let buildReleaseProof = make(
        id: "code_release_proof", name: "Release Proof", lane: .code, output: .proofPacket, defaultEffort: .high,
        description: "Before a slice closes, prove that the owner-visible claim is actually true.",
        rows: [
            row("acceptance_auditor", .answer, .low),
            row("test_runner_planner", .answer, .low),
            row("risk_register", .review, .low),
            row("edge_case_hunter", .answer, .med),
            row("contract_drift_checker", .answer, .med),
            row("demo_narrator", .review, .high)
        ], writer: "proof_packet_writer", dissent: .riskRegister)

    // MARK: - Design teams

    static let designCore = make(
        id: "design_core", name: "Design Core", lane: .design, output: .designBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a product/design prompt into several credible interface directions, then make the tradeoffs visible.",
        rows: [
            row("information_architect", .answer, .low),
            row("interaction_designer", .answer, .low),
            row("visual_system_designer", .answer, .low),
            row("accessibility_reviewer", .review, .med),
            row("brand_fit_reviewer", .review, .med),
            // Image/design tile is optional: disables (not blocks) when no image model is ready.
            row("outlier_direction", .answer, .high, required: false, tags: [.image], fallback: .anyReady),
            row("design_critic", .review, .high)
        ], writer: "design_board_writer", dissent: .compareOptions)

    static let designPremiumPolish = make(
        id: "design_premium_polish", name: "Premium Polish", lane: .design, output: .polishBoard, defaultEffort: .high,
        description: "Make an existing surface feel expensive, intentional, and native without changing its product semantics.",
        rows: [
            row("hierarchy_sculptor", .answer, .low),
            row("type_spacing_auditor", .answer, .low),
            row("color_token_keeper", .answer, .low),
            row("component_stylist", .answer, .med),
            row("state_designer", .answer, .med),
            row("polish_critic", .review, .high)
        ], writer: "polish_board_writer")

    static let designConversionStudio = make(
        id: "design_conversion_studio", name: "Conversion Studio", lane: .design, output: .designBoard, defaultEffort: .high,
        description: "Improve a product/marketing surface so users understand the offer, trust it, and know what to do next.",
        rows: [
            row("offer_clarity", .answer, .low),
            row("cta_path", .answer, .low),
            row("friction_hunter", .answer, .med),
            row("trust_builder", .answer, .med),
            row("mobile_scanner", .answer, .med),
            row("objection_finder", .review, .high)
        ], writer: "conversion_board_writer")

    static let designRadicalDirections = make(
        id: "design_radical_directions", name: "Radical Directions", lane: .design, output: .designBoard, defaultEffort: .med,
        description: "Generate genuinely different design directions before the team converges too early.",
        rows: [
            row("minimal_direction", .answer, .low),
            row("bold_direction", .answer, .low),
            row("operational_direction", .answer, .med),
            row("editorial_direction", .answer, .med),
            row("native_app_direction", .answer, .high),
            row("direction_critic", .review, .high)
        ], writer: "direction_board_writer", dissent: .compareOptions)

    static let designUsabilityTriage = make(
        id: "design_usability_triage", name: "Usability Triage", lane: .design, output: .polishBoard, defaultEffort: .med,
        description: "Find why a surface feels confusing, slow, risky, or hard to repeat.",
        rows: [
            row("journey_mapper", .answer, .low),
            row("control_ergonomics", .answer, .low),
            row("navigation_reviewer", .answer, .med),
            row("accessibility_reviewer", .review, .med),
            row("cognitive_load_cutter", .review, .high),
            row("state_feedback_reviewer", .review, .high)
        ], writer: "usability_triage_writer")

    // MARK: - Copy teams (parity; full type packs owned by docs/phases/copy)

    static let copyCore = make(
        id: "copy_core", name: "Copy Core", lane: .copy, output: .copyBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a copy prompt into clear, persuasive options grounded in the real offer.",
        rows: [
            row("offer_strategist", .answer, .low),
            row("headline_writer", .answer, .low),
            row("direct_response_writer", .answer, .med),
            row("objection_hunter", .answer, .med),
            row("cta_writer", .answer, .med),
            row("proof_skeptic", .review, .high),
            row("brand_voice", .review, .high)
        ], writer: "copy_board_writer")

    static let copyLandingPage = make(
        id: "copy_landing_page", name: "Landing Page Team", lane: .copy, output: .copyBoard, defaultEffort: .high,
        description: "Rewrite a landing page so the offer is clear, trusted, and converts.",
        rows: [
            row("offer_strategist", .answer, .low),
            row("headline_writer", .answer, .low),
            row("cta_writer", .answer, .low),
            row("direct_response_writer", .answer, .med),
            row("objection_hunter", .answer, .med),
            row("proof_skeptic", .review, .high),
            row("brand_voice", .review, .high)
        ], writer: "landing_copy_writer", typeTags: ["landing-page"])
}
