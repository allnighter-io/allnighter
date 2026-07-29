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

    public static func action(_ id: String) -> Pair? { actions[id] }

    public static func team(
        id: String,
        displayName: String,
        description: String,
        mutating: Bool
    ) -> Pair {
        if let authored = teams[id] { return authored }
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
        if let authored = models[id] { return authored }
        return Pair(
            useWhen: bound("Custom \(driverId) worker (\(displayName))", limit: useWhenMax),
            dontUseWhen: bound("Confirm id in menu; not a built-in seat", limit: dontUseWhenMax)
        )
    }

    public static func recipe(id: String, title: String) -> Pair {
        if let authored = recipes[id] { return authored }
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
        "run": Pair(
            useWhen: "Ask a worker/team; `--seat` staffs crew once",
            dontUseWhen: "Not catalog write; teams duplicate, teams edit"
        ),
        "teams duplicate": Pair(
            useWhen: "Copy a shipped team, edit it",
            dontUseWhen: "Not one-off staffing; run --seat"
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
        "code_spec_review_min": Pair(
            useWhen: "Lean spec check before you build",
            dontUseWhen: "Review only, no edits"
        ),
        "code_spec_review": Pair(
            useWhen: "Harden a spec before you build",
            dontUseWhen: "Review only, no edits"
        ),
        "code_spec_review_max": Pair(
            useWhen: "Deep review: launch/hard specs",
            dontUseWhen: "Review only, no edits"
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
        "model_chatgpt": Pair(
            useWhen: "ChatGPT 5.6 Sol, Codex (default)",
            dontUseWhen: "Not Cursor Sol; model_chatgpt_sol"
        ),
        "model_chatgpt_terra": Pair(
            useWhen: "ChatGPT 5.6 Terra, Codex (medium)",
            dontUseWhen: "Not Sol; use model_chatgpt"
        ),
        "model_chatgpt_54": Pair(
            useWhen: "ChatGPT 5.4, Codex (non-Sol)",
            dontUseWhen: "Not Sol; use model_chatgpt"
        ),
        "model_chatgpt_54_mini": Pair(
            useWhen: "ChatGPT 5.4 mini, Codex (lighter)",
            dontUseWhen: "Not Sol; use model_chatgpt"
        ),
        "model_codex_spark": Pair(
            useWhen: "Codex Spark, fast Codex seat",
            dontUseWhen: "Not Sol; use model_chatgpt"
        ),
        "model_grok": Pair(
            useWhen: "Grok 4.5, web-aware, images",
            dontUseWhen: "Not Cursor Grok; model_cursor_grok_45"
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
        "model_composer": Pair(
            useWhen: "Grok Composer 2.5 Fast (Grok)",
            dontUseWhen: "Not Cursor; model_cursor_composer_25"
        ),
        "model_cursor_auto": Pair(
            useWhen: "Cursor Auto, default agent",
            dontUseWhen: "Not pinned; pick an explicit id"
        ),
        "model_cursor_composer_25": Pair(
            useWhen: "Cursor Composer 2.5 impl seat",
            dontUseWhen: "Not Grok Composer; model_composer"
        ),
        "model_cursor_grok_45": Pair(
            useWhen: "Cursor-hosted Grok 4.5 seat",
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
        "model_chatgpt_sol": Pair(
            useWhen: "ChatGPT 5.6 Sol, Cursor (paid)",
            dontUseWhen: "Burns Cursor quota; model_chatgpt"
        ),
        "model_cursor_composer_25_fast": Pair(
            useWhen: "Cursor Composer 2.5 Fast, lighter",
            dontUseWhen: "Not full; model_cursor_composer_25"
        ),
        "model_gemini": Pair(
            useWhen: "Gemini 3.6 Flash, Antigravity",
            dontUseWhen: "Not Pro; model_gemini_pro"
        ),
        "model_gemini_pro": Pair(
            useWhen: "Gemini 3.1 Pro, Antigravity",
            dontUseWhen: "Not Flash; model_gemini"
        ),
        "model_agy_gptoss": Pair(
            useWhen: "GPT-OSS 120B, Antigravity",
            dontUseWhen: "Not Sol; model_chatgpt"
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
            useWhen: "You PM; a model builds (Pilot)",
            dontUseWhen: "Not single ask; run --model"
        ),
        "get-sols-take-without-changing-files": Pair(
            useWhen: "Read-only Sol ask; no file changes",
            dontUseWhen: "Not multi-seat; --model model_chatgpt"
        ),
        "keep-working-while-im-away": Pair(
            useWhen: "Unattended PM↔dev relay loop",
            dontUseWhen: "Not one-shot; use pair relay"
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
