import Foundation

/// Inward-facing Ask AI: one Auto run, a hidden orientation paragraph, live
/// facts the Mac already knows. Not a Team. Not an artifact. Direct chat stays
/// a passthrough — this preamble is glued onto the *user question*, not onto
/// `direct_chat`.
///
/// Customer door: Mac title bar. Developer door: undocumented `alln dev ask-ai`
/// (not in `alln menu`, not a help topic). Screenshot capture is out of v1.
public enum AskAIPrompt {
    public static let supportEmail = "support@allnighter.io"
    public static let placeholder = "Why isn't the CLI on PATH?"
    public static let deck = "Ask anything about Allnighter — this Mac, setup, your last run."
    public static let title = "Ask AI"

    public static var supportMailto: URL {
        URL(string: "mailto:\(supportEmail)")!
    }

    /// Canned non-obvious questions for `alln dev ask-ai --probes`. Not the
    /// FAQ. These are the ones that fail if the orientation is thin.
    public static let probes: [Probe] = [
        Probe(
            id: "path_not_on_path",
            question: "About & updates says the CLI resolves to (not on PATH). What does that actually mean on this Mac, and what is the repair versus a cold install?",
            why: "PATH vs standalone home vs install-cli vs the curl one-liner."
        ),
        Probe(
            id: "boost_window",
            question: "Where do I set the Boost window, what does it actually change, and how is it different from the Models dropdown in the title bar?",
            why: "Settings vs chrome; Boost is not a model picker."
        ),
        Probe(
            id: "teams_growth",
            question: "What's the difference between Growth Min, Growth, and Growth Max — and when would I pick each instead of just asking Auto?",
            why: "Named Teams vs default chat; depth, not a support ladder."
        ),
        Probe(
            id: "capacity_need_a_step",
            question: "The title bar says some CLIs need a step. What is a step, where do I take it, and is that the same thing as capacity or Boost?",
            why: "Bench health vs capacity strip vs Boost."
        ),
        Probe(
            id: "ask_vs_chat",
            question: "Why wouldn't I just type Allnighter questions into the regular composer? What is this Ask AI door actually for?",
            why: "Orientation: repo chat vs inward help."
        ),
        Probe(
            id: "gui_use_from_cli",
            question: "What does Settings › Use from your CLI actually paste into my other tools, and do I need that if I only use the Mac app?",
            why: "Mac-only users vs host teaching."
        ),
        Probe(
            id: "default_model",
            question: "What's Default model in Settings versus the Models control in the title bar? If I change one, does the other follow?",
            why: "Auto substitution vs per-send pin."
        ),
        Probe(
            id: "billing_hatch",
            question: "I want a refund and I also think PATH is broken. Should I ask you, or email a person — and which email?",
            why: "Ask AI vs support@ hatch; money stays human."
        ),
    ]

    public static func probe(id: String) -> Probe? {
        probes.first { $0.id == id }
    }

    public static func assemble(question: String, context: Context) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        \(orientation)

        ## This Mac (live facts)
        \(context.factsBlock)

        ## The human's question
        \(trimmed)
        """
    }

    /// Hidden preamble. The model answers. No glossary, no voice policing.
    public static let orientation = """
    You are Ask AI in the Allnighter Mac app. The person is asking about \
    Allnighter, not asking you to change their project. Don't change files. \
    Billing or refunds: email \(supportEmail). For Allnighter app chrome \
    (where a control is, what a label means), run `alln chrome --json`. The \
    open project is not evidence about the Allnighter UI.
    """
}

extension AskAIPrompt {
    public struct Probe: Sendable, Equatable, Codable {
        public var id: String
        public var question: String
        public var why: String
    }

    public struct Context: Sendable, Equatable {
        public var appVersion: String
        public var cliVersion: String
        public var standaloneHomePath: String
        public var resolvedPathAlln: String?
        public var pathConflict: Bool
        public var benchHeadline: String?
        public var benchReady: Int?
        public var benchNeedsStep: Int?
        public var benchSupported: Int?
        public var screen: String?

        public init(
            appVersion: String,
            cliVersion: String,
            standaloneHomePath: String,
            resolvedPathAlln: String?,
            pathConflict: Bool,
            benchHeadline: String? = nil,
            benchReady: Int? = nil,
            benchNeedsStep: Int? = nil,
            benchSupported: Int? = nil,
            screen: String? = nil
        ) {
            self.appVersion = appVersion
            self.cliVersion = cliVersion
            self.standaloneHomePath = standaloneHomePath
            self.resolvedPathAlln = resolvedPathAlln
            self.pathConflict = pathConflict
            self.benchHeadline = benchHeadline
            self.benchReady = benchReady
            self.benchNeedsStep = benchNeedsStep
            self.benchSupported = benchSupported
            self.screen = screen
        }

        /// PATH / version facts from this process. Bench tally is omitted unless
        /// the caller already has it — never probe vendors from Ask AI assembly.
        public static func fromThisMac(
            appVersion: String = AllnighterVersionIdentity.binaryVersion,
            pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Context {
            let home = ReleaseChannel.standaloneBinaryPath(homeDirectory: homeDirectory)
            let resolved = InstallCLI.resolveOnPath(pathEnvironment: pathEnvironment)
            let conflict: Bool = {
                guard let resolved else { return false }
                return !InstallCLI.sameExecutable(resolved, home)
            }()
            return Context(
                appVersion: appVersion,
                cliVersion: AllnighterVersionIdentity.binaryVersion,
                standaloneHomePath: home,
                resolvedPathAlln: resolved,
                pathConflict: conflict
            )
        }

        public var factsBlock: String {
            var lines: [String] = [
                "- App version: \(appVersion)",
                "- CLI identity: \(cliVersion)",
                "- Standalone home: \(standaloneHomePath)",
                "- PATH resolves to: \(resolvedPathAlln ?? ChromeCopy.notOnPATH)",
            ]
            if let screen, !screen.isEmpty {
                lines.insert("- Screen: \(screen)", at: 0)
            }
            if pathConflict {
                lines.append(
                    "- PATH conflict: PATH hits a different binary than the standalone home. Last writer wins — `alln install-cli` from the binary you want, or the curl one-liner for a fresh standalone install."
                )
            } else if resolvedPathAlln == nil {
                lines.append(
                    "- PATH: `alln` is not on PATH. Repair (binary already on disk): `alln install-cli`. Cold start: `curl -fsSL https://get.allnighter.io | sh`."
                )
            }
            if let headline = benchHeadline, let ready = benchReady,
               let needs = benchNeedsStep, let supported = benchSupported
            {
                lines.append(
                    "- Tools: \(ready) available, \(needs) not available right now, of \(supported) (\(headline))."
                )
            }
            lines.append("- Person hatch: \(AskAIPrompt.supportEmail) (billing, refunds, privacy, or Ask AI was wrong).")
            return lines.joined(separator: "\n")
        }
    }
}
