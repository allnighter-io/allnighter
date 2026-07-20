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
            useWhen: "Ask one worker or Send-to-team (starts work)",
            dontUseWhen: "Not for catalog write — teams duplicate/new/edit"
        ),
        "teams duplicate": Pair(
            useWhen: "Copy shipped team before definition→edit",
            dontUseWhen: "Not for run; novel manifest → teams new"
        ),
        "teams new": Pair(
            useWhen: "Create novel team from TeamPreset JSON",
            dontUseWhen: "Not for run; shipped variants → teams duplicate"
        ),
        "teams edit": Pair(
            useWhen: "Replace custom team JSON after dup/new",
            dontUseWhen: "Not for run; copy → duplicate; first create → new"
        ),
        "models": Pair(
            useWhen: "List Bench models (domain catalog view)",
            dontUseWhen: "Not for selection — prefer `menu`; not for spend — use `run`"
        ),
    ]

    private static let teams: [String: Pair] = [
        "default_chat": Pair(
            useWhen: "Default chat/build agent in the repo root",
            dontUseWhen: "Not multi-seat judgment — pick an answer team id"
        ),
        "build_slice": Pair(
            useWhen: "Mutating slice: edit → proof → deslop → commit",
            dontUseWhen: "Not for parallel judgment — use an answer team"
        ),
        "code_plan": Pair(
            useWhen: "Turn a rough idea into an implementable plan",
            dontUseWhen: "Not for writing code — use team build_slice"
        ),
        "code_bug_hunt_min": Pair(
            useWhen: "Lean bug cause hunt + smallest fix plan",
            dontUseWhen: "Not for mutating fix — use build_slice after plan"
        ),
        "code_bug_hunt": Pair(
            useWhen: "Full bug cause hunt: reproduce, owner, fix plan",
            dontUseWhen: "Not for mutating fix — use build_slice after plan"
        ),
        "code_bug_hunt_max": Pair(
            useWhen: "Escalation bug hunt for seam/state failures",
            dontUseWhen: "Not for mutating fix — use build_slice after plan"
        ),
        "code_gui_bug_hunt": Pair(
            useWhen: "Native GUI breakage with rendered proof",
            dontUseWhen: "Not for non-UI bugs — use code_bug_hunt"
        ),
        "code_security_review": Pair(
            useWhen: "Privacy/credentials/permissions risk review",
            dontUseWhen: "Not for implementing fixes — answer team only"
        ),
        "code_growth_min": Pair(
            useWhen: "Lean growth read: find the simple wedge",
            dontUseWhen: "Not for writing code — judgment only"
        ),
        "code_growth": Pair(
            useWhen: "Multi-model growth: wedge builders will love",
            dontUseWhen: "Not for writing code — judgment only"
        ),
        "code_growth_max": Pair(
            useWhen: "Deep growth + outside signal on what spreads",
            dontUseWhen: "Not for writing code — judgment only"
        ),
        "code_spec_review_min": Pair(
            useWhen: "Lean spec check before you build",
            dontUseWhen: "Not for implementing — review only"
        ),
        "code_spec_review": Pair(
            useWhen: "Harden a feature/phase spec before build",
            dontUseWhen: "Not for implementing — review only"
        ),
        "code_spec_review_max": Pair(
            useWhen: "Full-depth launch/hard-spec blind review",
            dontUseWhen: "Not for implementing — review only"
        ),
        "code_release_proof": Pair(
            useWhen: "Prove the owner-visible claim before close",
            dontUseWhen: "Not for new feature work — proof packet only"
        ),
        "design_design_min": Pair(
            useWhen: "Quick design take + one mockup direction",
            dontUseWhen: "Not for shipping code — design craft only"
        ),
        "design_design": Pair(
            useWhen: "Design/redesign a screen with option tradeoffs",
            dontUseWhen: "Not for shipping code — design craft only"
        ),
        "design_design_max": Pair(
            useWhen: "Wide design divergence before converging",
            dontUseWhen: "Not for shipping code — design craft only"
        ),
        "design_polish": Pair(
            useWhen: "Polish an existing surface; no semantic change",
            dontUseWhen: "Not for redesign from scratch — use design_design"
        ),
        "design_usability_review": Pair(
            useWhen: "Diagnose confusing/slow/risky UI friction",
            dontUseWhen: "Not for visual polish alone — use design_polish"
        ),
        "copy_core": Pair(
            useWhen: "Clear persuasive copy options for an offer",
            dontUseWhen: "Not for landing pages — use copy_landing"
        ),
        "copy_landing": Pair(
            useWhen: "Rewrite a landing page so the offer converts",
            dontUseWhen: "Not for short UI microcopy — use copy_core"
        ),
        "signal_outside": Pair(
            useWhen: "Distill a public post/link into project insight",
            dontUseWhen: "Not for repo code changes — signal craft only"
        ),
        "signal_what_to_build_next": Pair(
            useWhen: "Outside scan → next build direction for project",
            dontUseWhen: "Not for implementing the idea — signal only"
        ),
    ]

    private static let models: [String: Pair] = [
        "model_fable": Pair(
            useWhen: "Claude Fable 5 flagship judgment/code seat",
            dontUseWhen: "Not a team — pass --worker model_fable"
        ),
        "model_opus": Pair(
            useWhen: "Claude Opus 4.8 deep judgment seat",
            dontUseWhen: "Not a team — pass --worker model_opus"
        ),
        "model_sonnet": Pair(
            useWhen: "Claude Sonnet 5 fast review/code seat",
            dontUseWhen: "Not a team — pass --worker model_sonnet"
        ),
        "model_chatgpt": Pair(
            useWhen: "ChatGPT 5.6 Sol via Codex (default Sol)",
            dontUseWhen: "Not Cursor Sol — that is model_chatgpt_sol"
        ),
        "model_chatgpt_54": Pair(
            useWhen: "ChatGPT 5.4 via Codex (non-Sol)",
            dontUseWhen: "Not Sol — prefer model_chatgpt for Sol"
        ),
        "model_chatgpt_54_mini": Pair(
            useWhen: "ChatGPT 5.4 mini via Codex (lighter)",
            dontUseWhen: "Not Sol — prefer model_chatgpt for Sol"
        ),
        "model_codex_spark": Pair(
            useWhen: "Codex Spark fast Codex-family seat",
            dontUseWhen: "Not Sol — prefer model_chatgpt for Sol"
        ),
        "model_grok": Pair(
            useWhen: "Grok 4.5 web-aware / image-capable seat",
            dontUseWhen: "Not Cursor Grok — that is model_cursor_grok_45"
        ),
        "model_kimi_k3": Pair(
            useWhen: "Kimi K3 strong design/code judgment seat",
            dontUseWhen: "Not a team — pass --worker model_kimi_k3"
        ),
        "model_composer": Pair(
            useWhen: "Grok Composer 2.5 Fast (Grok driver)",
            dontUseWhen: "Not Cursor Composer — model_cursor_composer_25"
        ),
        "model_cursor_auto": Pair(
            useWhen: "Cursor Auto default Cursor Agent seat",
            dontUseWhen: "Not for pinned model — pick an explicit id"
        ),
        "model_cursor_composer_25": Pair(
            useWhen: "Cursor Composer 2.5 implementation seat",
            dontUseWhen: "Not Grok Composer — that is model_composer"
        ),
        "model_cursor_grok_45": Pair(
            useWhen: "Cursor-hosted Grok 4.5 seat",
            dontUseWhen: "Not native Grok CLI — that is model_grok"
        ),
        "model_chatgpt_sol": Pair(
            useWhen: "ChatGPT 5.6 Sol via Cursor (paid quota)",
            dontUseWhen: "Burns Cursor quota — prefer model_chatgpt"
        ),
        "model_cursor_composer_25_fast": Pair(
            useWhen: "Cursor Composer 2.5 Fast lighter seat",
            dontUseWhen: "Not full Composer — model_cursor_composer_25"
        ),
        "model_gemini": Pair(
            useWhen: "Gemini 3.5 Flash via Antigravity",
            dontUseWhen: "Not Pro — that is model_gemini_pro"
        ),
        "model_gemini_pro": Pair(
            useWhen: "Gemini 3.1 Pro via Antigravity",
            dontUseWhen: "Not Flash — that is model_gemini"
        ),
        "model_agy_sonnet": Pair(
            useWhen: "Claude Sonnet 4.6 via Antigravity",
            dontUseWhen: "Not Claude Code Sonnet — model_sonnet"
        ),
        "model_agy_opus": Pair(
            useWhen: "Claude Opus 4.6 via Antigravity",
            dontUseWhen: "Not Claude Code Opus — model_opus"
        ),
        "model_agy_gptoss": Pair(
            useWhen: "GPT-OSS 120B via Antigravity",
            dontUseWhen: "Not a ChatGPT Sol seat — model_chatgpt"
        ),
        "model_opencode_qwen3_coder_next": Pair(
            useWhen: "Qwen3 Coder Next via OpenCode BYOK",
            dontUseWhen: "Needs OpenCode/BYOK ready — check doctor"
        ),
        "model_opencode_glm_5_2": Pair(
            useWhen: "GLM 5.2 via OpenCode BYOK",
            dontUseWhen: "Needs OpenCode/BYOK ready — check doctor"
        ),
    ]

    private static let recipes: [String: Pair] = [
        "ask-several-models-and-compare": Pair(
            useWhen: "Want parallel options from a multi-seat team",
            dontUseWhen: "Not one worker — use run --worker for a single ask"
        ),
        "challenge-this-decision-before-i-commit": Pair(
            useWhen: "Blind-jury a decision/spec before committing",
            dontUseWhen: "Not for implementing — Spec Review / Panel only"
        ),
        "get-another-model-to-implement-this": Pair(
            useWhen: "You PM; another model builds under Pilot",
            dontUseWhen: "Not a single chat ask — that is run --worker"
        ),
        "get-sols-take-without-changing-files": Pair(
            useWhen: "Read-only Sol ask; no file changes",
            dontUseWhen: "Not multi-seat — use run --worker model_chatgpt"
        ),
        "keep-working-while-im-away": Pair(
            useWhen: "Unattended PM↔dev relay overnight loop",
            dontUseWhen: "Not a one-shot run — use pair relay"
        ),
        "recover-a-run-that-lost-its-terminal": Pair(
            useWhen: "Monitor/cancel a run after shell is gone",
            dontUseWhen: "Not for starting new work — use run"
        ),
        "use-a-specific-model-without-silent-substitution": Pair(
            useWhen: "Pin an exact worker id; no silent swap",
            dontUseWhen: "Not display-name dispatch — pass canonical id"
        ),
    ]

    private static func bound(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit - 1)
        return String(trimmed[..<idx]) + "…"
    }
}
