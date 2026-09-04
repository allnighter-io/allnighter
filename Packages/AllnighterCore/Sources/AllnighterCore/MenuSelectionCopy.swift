import Foundation

/// Authored selection-grade `useWhen` / `dontUseWhen` for menu rows (MR-S03).
/// `MenuCatalog` reads this map — derived stubs do not satisfy the gate.
public enum MenuSelectionCopy {
    public static let useWhenMax = 48
    public static let dontUseWhenMax = 72
    /// Declared template variables across menu templates (`{name}` syntax).
    public static let declaredTemplateVariables: Set<String> = ["message", "ref"]

    public struct Pair: Equatable, Sendable {
        public var useWhen: String
        public var dontUseWhen: String

        public init(useWhen: String, dontUseWhen: String) {
            self.useWhen = useWhen
            self.dontUseWhen = dontUseWhen
        }
    }

    public enum BoundError: Error, Equatable, CustomStringConvertible {
        case useWhenTooLong(kind: String, id: String, length: Int)
        case dontUseWhenTooLong(kind: String, id: String, length: Int)
        case empty(kind: String, id: String, field: String)

        public var description: String {
            switch self {
            case .useWhenTooLong(let kind, let id, let length):
                return "\(kind) \(id) useWhen length \(length) > \(useWhenMax)"
            case .dontUseWhenTooLong(let kind, let id, let length):
                return "\(kind) \(id) dontUseWhen length \(length) > \(dontUseWhenMax)"
            case .empty(let kind, let id, let field):
                return "\(kind) \(id) \(field) is empty"
            }
        }
    }

    /// Old derived / generic prose that must not appear as authored selection copy.
    public static let bannedStubs: Set<String> = [
        "Pick from menu.recipes only",
        "Pick from menu",
        "Pick from menu…",
        "Not for parallel judgment",
        "Not for mutating/write runs",
        "Do NOT use this when you need the selec…",
    ]

    // MARK: - Lookups

    public static func action(_ id: String) -> Pair? {
        actions[id].map(projected)
    }

    public static func team(
        id: String,
        displayName: String,
        description: String,
        mutating: Bool
    ) -> Pair {
        if let authored = teams[id] { return projected(authored) }
        let use: String
        if !description.isEmpty {
            use = bound(description, limit: useWhenMax)
        } else {
            use = bound("Custom team \(displayName)", limit: useWhenMax)
        }
        let dont = mutating
            ? "Custom mutating; inspect via teams show \(id)"
            : "Custom answer team; inspect via teams show \(id)"
        return Pair(useWhen: use, dontUseWhen: bound(dont, limit: dontUseWhenMax))
    }

    public static func model(id: String, displayName: String, driverId: String) -> Pair {
        // Authored path must bound too — returning verbatim used to crash
        // `MenuCatalog.project` when a useWhen typo exceeded useWhenMax.
        if let authored = models[id] { return projected(authored) }
        return Pair(
            useWhen: bound("Custom \(driverId) worker (\(displayName))", limit: useWhenMax),
            dontUseWhen: bound("Confirm id in menu; not a built-in seat", limit: dontUseWhenMax)
        )
    }

    public static func recipe(id: String, title: String) -> Pair {
        if let authored = recipes[id] { return projected(authored) }
        return Pair(
            useWhen: bound(title, limit: useWhenMax),
            dontUseWhen: bound("Custom recipe; read markdown via menu show", limit: dontUseWhenMax)
        )
    }

    // MARK: - Validation

    public static func validateBounds(_ pair: Pair, kind: String, id: String) throws {
        let use = pair.useWhen.trimmingCharacters(in: .whitespacesAndNewlines)
        let dont = pair.dontUseWhen.trimmingCharacters(in: .whitespacesAndNewlines)
        if use.isEmpty { throw BoundError.empty(kind: kind, id: id, field: "useWhen") }
        if dont.isEmpty { throw BoundError.empty(kind: kind, id: id, field: "dontUseWhen") }
        if use.count > useWhenMax {
            throw BoundError.useWhenTooLong(kind: kind, id: id, length: use.count)
        }
        if dont.count > dontUseWhenMax {
            throw BoundError.dontUseWhenTooLong(kind: kind, id: id, length: dont.count)
        }
    }

    /// Bound/truncate selection copy for safe projection. A copy-length typo
    /// must never crash the agent front door; build-time tests gate authorship.
    public static func projected(_ pair: Pair) -> Pair {
        Pair(
            useWhen: bound(pair.useWhen, limit: useWhenMax),
            dontUseWhen: bound(pair.dontUseWhen, limit: dontUseWhenMax)
        )
    }

    /// Every authored table entry (actions, teams, models, recipes) for the
    /// build-time bounds gate. Runtime projection degrades; this is the loud fail.
    public static func authoredEntries() -> [(kind: String, id: String, pair: Pair)] {
        actions.map { (kind: "action", id: $0.key, pair: $0.value) }
            + teams.map { (kind: "team", id: $0.key, pair: $0.value) }
            + models.map { (kind: "model", id: $0.key, pair: $0.value) }
            + recipes.map { (kind: "recipe", id: $0.key, pair: $0.value) }
    }

    /// Extract `{name}` placeholders from a template string.
    public static func templateVariables(in template: String) -> Set<String> {
        var names: Set<String> = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else { break }
            let name = String(rest[afterOpen..<close])
            if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                names.insert(name)
            }
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    public static func isBannedStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if bannedStubs.contains(trimmed) { return true }
        if trimmed.hasPrefix("Pick from menu") { return true }
        return false
    }

    // MARK: - Authored tables

    private static let actions: [String: Pair] = [
        // `--read-only` earns the scarce useWhen slot because omitting it costs
        // real money: the menu is the prescribed front door, so an agent that
        // follows it dispatches every investigation as a mutating run — taking
        // the repo write lock (serializing parallel reviews behind each other)
        // and tripping the incomplete_uncommitted gate on a delivered answer.
        // `--seat` moves to dontUseWhen, which has the headroom, rather than
        // being dropped.
        "run": Pair(
            useWhen: "Ask worker/team; --read-only to investigate",
            dontUseWhen: "Not catalog write; teams duplicate/edit; --seat"
        ),
        "teams duplicate": Pair(
            useWhen: "Copy a shipped team, edit it",
            dontUseWhen: "Not staffing; run --seat"
        ),
        "teams new": Pair(
            useWhen: "Create novel team from TeamPreset JSON",
            dontUseWhen: "Not for run; shipped variants → teams duplicate"
        ),
        "teams edit": Pair(
            useWhen: "Replace a custom team's JSON",
            dontUseWhen: "Not run; copy=duplicate, create=new"
        ),
        "models": Pair(
            useWhen: "List Bench models (catalog view)",
            dontUseWhen: "Not selection (`menu`) or spend (`run`)"
        ),
        "drivers": Pair(
            useWhen: "List CLIs; see parked vs ready",
            dontUseWhen: "Not model pick (`menu`); park via drivers park"
        ),
    ]

    private static let teams: [String: Pair] = [
        "default_chat": Pair(
            useWhen: "Default repo chat/build agent",
            dontUseWhen: "Not multi-seat; pick a team"
        ),
        "build_slice": Pair(
            useWhen: "Edit → proof → deslop → commit",
            dontUseWhen: "Not judgment; pick an answer team"
        ),
        "code_plan": Pair(
            useWhen: "A rough idea into a plan",
            dontUseWhen: "Not code; use build_slice"
        ),
        "code_bug_hunt_min": Pair(
            useWhen: "Fastest cause hunt + smallest fix",
            dontUseWhen: "Not mutating; build_slice"
        ),
        "code_bug_hunt": Pair(
            useWhen: "Cause hunt: reproduce, owner, fix",
            dontUseWhen: "Not mutating; build_slice"
        ),
        "code_bug_hunt_max": Pair(
            useWhen: "Deep hunt: seam-crossing, hidden state",
            dontUseWhen: "Not mutating; build_slice"
        ),
        "code_gui_bug_hunt": Pair(
            useWhen: "GUI breakage with rendered proof",
            dontUseWhen: "Not non-UI; use code_bug_hunt"
        ),
        "code_security_review": Pair(
            useWhen: "Privacy/credentials/permissions",
            dontUseWhen: "Not implementing; review only"
        ),
        "code_growth_min": Pair(
            useWhen: "Fast growth: the simple wedge",
            dontUseWhen: "Judgment, not code"
        ),
        "code_growth": Pair(
            useWhen: "Multi-model growth: loved wedge",
            dontUseWhen: "Judgment, not code"
        ),
        "code_growth_max": Pair(
            useWhen: "Deep growth + live trend signal",
            dontUseWhen: "Judgment, not code"
        ),
        "fusion": Pair(
            useWhen: "Fusion control: same prompt, fixed panel",
            dontUseWhen: "Different seats; code_spec_review"
        ),
        "code_spec_review_min": Pair(
            useWhen: "Lean spec check before you build",
            dontUseWhen: "Review only, no edits"
        ),
        "code_doc_review": Pair(
            useWhen: "One-model doc/spec feedback, no mutator queue",
            dontUseWhen: "Build/edit code; use Auto or Build a Slice"
        ),
        "code_spec_review": Pair(
            useWhen: "Harden a spec before you build",
            dontUseWhen: "Review only; no edits"
        ),
        "code_spec_review_max": Pair(
            useWhen: "Deep review: launch/hard specs",
            dontUseWhen: "Review only; no edits"
        ),
        "code_release_proof": Pair(
            useWhen: "Prove the owner-visible claim",
            dontUseWhen: "Not new work; proof only"
        ),
        "design_design_min": Pair(
            useWhen: "Quick design take, one mockup",
            dontUseWhen: "Design craft only, no code"
        ),
        "design_design": Pair(
            useWhen: "Design a screen; tradeoffs shown",
            dontUseWhen: "Design craft only, no code"
        ),
        "design_design_max": Pair(
            useWhen: "Wide divergence before converging",
            dontUseWhen: "Design craft only, no code"
        ),
        "design_polish": Pair(
            useWhen: "Polish a surface, same semantics",
            dontUseWhen: "Not redesign; design_design"
        ),
        "design_usability_review": Pair(
            useWhen: "Diagnose confusing/slow friction",
            dontUseWhen: "Not visual polish; design_polish"
        ),
        "copy_core": Pair(
            useWhen: "Persuasive copy for an offer",
            dontUseWhen: "Not landing pages; copy_landing"
        ),
        "copy_landing": Pair(
            useWhen: "Rewrite a landing page to convert",
            dontUseWhen: "Not short UI copy; copy_core"
        ),
        "signal_outside": Pair(
            useWhen: "Post, video, or article: what it means here",
            dontUseWhen: "Not repo changes; signal only"
        ),
        "signal_what_to_build_next": Pair(
            useWhen: "Outside scan; next direction",
            dontUseWhen: "Not implementing; signal only"
        ),
        "code_ai_readiness": Pair(
            useWhen: "Audit agent workability (first Code Team)",
            dontUseWhen: "Not mutating; reports gaps, you decide"
        ),
    ]

    private static let models: [String: Pair] = [
        "model_fable": Pair(
            useWhen: "Claude Fable 5, flagship judgment",
            dontUseWhen: "Pin seat; model_fable"
        ),
        "model_opus": Pair(
            useWhen: "Claude Opus 5 deep judgment",
            dontUseWhen: "Pin seat; model_opus"
        ),
        "model_sonnet": Pair(
            useWhen: "Claude Sonnet 5 fast review/code",
            dontUseWhen: "Pin seat; model_sonnet"
        ),
        "model_gpt_sol": Pair(
            useWhen: "GPT-5.6 Sol, Codex (default)",
            dontUseWhen: "Not Cursor Sol; model_cursor_gpt_sol"
        ),
        "model_gpt_terra": Pair(
            useWhen: "GPT-5.6 Terra, Codex (medium)",
            dontUseWhen: "Not Sol; use model_gpt_sol"
        ),
        "model_gpt_luna": Pair(
            useWhen: "Codex economy seat, high effort default",
            dontUseWhen: "Not Sol/Terra; use model_gpt_sol or model_gpt_terra"
        ),
        "model_gpt_54": Pair(
            useWhen: "GPT-5.4, Codex (non-Sol)",
            dontUseWhen: "Not Sol; use model_gpt_sol"
        ),
        "model_gpt_54_mini": Pair(
            useWhen: "GPT-5.4 mini, Codex (lighter)",
            dontUseWhen: "Not Sol; use model_gpt_sol"
        ),
        "model_gpt_spark": Pair(
            useWhen: "GPT Spark, fast Codex seat",
            dontUseWhen: "Not Sol; use model_gpt_sol"
        ),
        "model_grok": Pair(
            useWhen: "Latest Grok on the Grok CLI (catalog-resolved)",
            dontUseWhen: "Need an exact generation; pin model_grok_46 or model_grok_45"
        ),
        "model_grok_45": Pair(
            useWhen: "Pin Grok 4.5 exactly",
            dontUseWhen: "Want latest Grok; use model_grok"
        ),
        "model_grok_46": Pair(
            useWhen: "Grok 4.6 frontier seat, web-aware, images",
            dontUseWhen: "Not Cursor Grok; model_cursor_grok_46"
        ),
        "model_kimi_k3": Pair(
            useWhen: "Kimi K3, design/code judgment",
            dontUseWhen: "Pin seat; model_kimi_k3"
        ),
        "model_kimi_k27": Pair(
            useWhen: "Kimi K2.7 Code, prior-gen coding",
            dontUseWhen: "Prefer K3; model_kimi_k27"
        ),
        "model_kimi_k27_hs": Pair(
            useWhen: "Kimi K2.7 HighSpeed, plan-gated fast",
            dontUseWhen: "Prefer K3; model_kimi_k27_hs"
        ),
        "model_muse_spark_13_contributor": Pair(
            useWhen: "Muse Spark 1.3 Contributor via Muse Code CLI",
            dontUseWhen: "Meta Muse login required; not OpenCode Go"
        ),
        "model_opencode_big_pickle": Pair(
            useWhen: "OpenCode Zen Big Pickle, free smoke/default",
            dontUseWhen: "Not Go; prefer Go seats when subscribed"
        ),
        "model_opencode_qwen_38_max": Pair(
            useWhen: "Qwen 3.8 Max, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_qwen_38_max": Pair(
            useWhen: "Qwen 3.8 Max, Qwen Code CLI",
            dontUseWhen: "Pin seat; model_qwen_38_max"
        ),
        "model_opencode_deepseek_v4_pro": Pair(
            useWhen: "DeepSeek V4 Pro, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_opencode_glm_5_2": Pair(
            useWhen: "GLM-5.2, OpenCode Go (prior gen)",
            dontUseWhen: "Prefer GLM-5.3; model_opencode_glm_5_3"
        ),
        "model_opencode_glm_5_3": Pair(
            useWhen: "GLM-5.3, OpenCode Go",
            dontUseWhen: "Prefer GLM-5.3-Flash for speed; model_opencode_glm_5_3_flash"
        ),
        "model_opencode_glm_5_3_flash": Pair(
            useWhen: "GLM-5.3-Flash, OpenCode Go",
            dontUseWhen: "Prefer GLM-5.3 for max depth; model_opencode_glm_5_3"
        ),
        "model_opencode_qwen_37_max": Pair(
            useWhen: "Qwen 3.7 Max, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_opencode_minimax_m3": Pair(
            useWhen: "MiniMax M3, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_opencode_deepseek_v4_flash": Pair(
            useWhen: "DeepSeek V4 Flash, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_opencode_qwen_37_plus": Pair(
            useWhen: "Qwen 3.7 Plus, OpenCode Go",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_opencode_ox_alpha_free": Pair(
            useWhen: "Ox Alpha Free, OpenCode Go (limited-time free seat)",
            dontUseWhen: "OpenCode Go required"
        ),
        "model_grok_composer_25_fast": Pair(
            useWhen: "Grok Composer 2.5 Fast (Grok)",
            dontUseWhen: "Not Cursor; model_cursor_composer_25"
        ),
        "model_cursor_auto": Pair(
            useWhen: "Cursor Auto, default agent",
            dontUseWhen: "Not pinned; pick an explicit id"
        ),
        "model_cursor_composer_25": Pair(
            useWhen: "Cursor Composer 2.5 impl seat",
            dontUseWhen: "Not Grok Composer; model_grok_composer_25_fast"
        ),
        "model_cursor_grok_45": Pair(
            useWhen: "Cursor-hosted Grok 4.5 seat",
            dontUseWhen: "Prefer Grok 4.6; model_cursor_grok_46"
        ),
        "model_cursor_grok_46": Pair(
            useWhen: "Cursor-hosted Grok 4.6 frontier seat",
            dontUseWhen: "Not native Grok CLI; model_grok"
        ),
        "model_cursor_fable": Pair(
            useWhen: "Fable 5 on Cursor",
            dontUseWhen: "Not Claude CLI; model_fable"
        ),
        "model_cursor_opus": Pair(
            useWhen: "Opus 5 on Cursor",
            dontUseWhen: "Not Claude CLI; model_opus"
        ),
        "model_cursor_sonnet": Pair(
            useWhen: "Sonnet 5 on Cursor",
            dontUseWhen: "Not Claude CLI; model_sonnet"
        ),
        "model_cursor_gpt_sol": Pair(
            useWhen: "GPT-5.6 Sol, Cursor (paid)",
            dontUseWhen: "Burns Cursor quota; model_gpt_sol"
        ),
        "model_cursor_composer_25_fast": Pair(
            useWhen: "Cursor Composer 2.5 Fast, lighter",
            dontUseWhen: "Not full; model_cursor_composer_25"
        ),
        "model_gemini": Pair(
            useWhen: "Gemini 3.8 Flash, Antigravity",
            dontUseWhen: "Not Gemini; other vendor seats"
        ),
        "model_agy_gptoss": Pair(
            useWhen: "GPT-OSS 120B, Antigravity",
            dontUseWhen: "Not Sol; model_gpt_sol"
        ),
        "model_agy_opus": Pair(
            useWhen: "Opus 4.6, Antigravity Claude pool",
            dontUseWhen: "Not Claude CLI; model_opus"
        ),
        "model_agy_sonnet": Pair(
            useWhen: "Sonnet 4.6, Antigravity Claude pool",
            dontUseWhen: "Not Claude CLI; model_sonnet"
        ),
    ]

    private static let recipes: [String: Pair] = [
        "ask-several-models-and-compare": Pair(
            useWhen: "Parallel options, multi-seat team",
            dontUseWhen: "Not one worker; run --model"
        ),
        "challenge-this-decision-before-i-commit": Pair(
            useWhen: "Blind-jury a decision pre-commit",
            dontUseWhen: "Not implementing; Spec Review"
        ),
        "get-another-model-to-implement-this": Pair(
            useWhen: "You PM; a model builds (loop --pm caller)",
            dontUseWhen: "Not single ask; run --model"
        ),
        "get-sols-take-without-changing-files": Pair(
            useWhen: "Read-only Sol ask; no file changes",
            dontUseWhen: "Not multi-seat; --model model_gpt_sol"
        ),
        "keep-working-while-im-away": Pair(
            useWhen: "Unattended PM↔dev loop",
            dontUseWhen: "Not one-shot; use run"
        ),
        "recover-a-run-that-lost-its-terminal": Pair(
            useWhen: "Monitor/cancel a run, shell is gone",
            dontUseWhen: "Not new work; use run"
        ),
        "use-a-specific-model-without-silent-substitution": Pair(
            useWhen: "Pin an exact worker id; no silent swap",
            dontUseWhen: "Not display-name; canonical id"
        ),
    ]

    private static func bound(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit - 1)
        return String(trimmed[..<idx]) + "…"
    }
}
