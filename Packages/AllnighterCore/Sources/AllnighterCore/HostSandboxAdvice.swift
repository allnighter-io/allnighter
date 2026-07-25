import Foundation

/// When Allnighter runs inside a host that sandboxes it (today: Codex), the
/// worker CLIs cannot reach the Keychain to authenticate, so every seat fails to
/// start. That used to surface as an unexplained empty run.
///
/// This turns that one specific failure into an honest answer with two ways
/// forward. It is deliberately written for someone who does not read code: no
/// "sandbox", no "Keychain", no "spawn".
///
/// Detection is on the observed FAILURE, never on the environment alone — a
/// Codex session launched with full access still carries the same environment
/// variables and runs perfectly, so pre-empting on those would block work that
/// would have succeeded. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
public struct HostSandboxAdvice: Equatable, Sendable {
    public static let code = "HOST_SANDBOX_BLOCKS_WORKERS"

    /// Signatures observed live from vendor CLIs started inside a Codex sandbox.
    ///
    /// These only count alongside a restricted host (see the `CODEX_SANDBOX` guard
    /// in `detect`) — in a normal Terminal "Not logged in" means exactly what it
    /// says and must never be explained away. That guard is what makes it safe to
    /// match broadly here.
    ///
    /// Matching vendor prose is a losing game and this list is the fallback, not
    /// the primary signal: `capacityAuthRequired` below is a TYPED fact. The list
    /// grew after a live run in which two of three seats died on
    /// `SecItemCopyMatching failed -67674` and `capacity: authRequired`, neither of
    /// which matched the original three strings — so the hand-off never fired and
    /// the founder silently got one seat of a three-seat team.
    static let failureSignatures = [
        // Codex app-server / PATH
        "failed to initialize in-process app-server client",
        "could not create PATH aliases",
        // Vendor-reported sign-in state
        "Not logged in",
        "not authenticated",
        // Keychain denial (cursor-agent, and anything using SecItem)
        "SecItemCopyMatching",
        "errSecInteractionNotAllowed",
        "keychain",
        // Filesystem / process denials the sandbox produces (kimi, grok, codex)
        "Operation not permitted",
        "operation not permitted",
        "FS_PERMISSION_DENIED",
        "EPERM",
        "Permission denied",
    ]

    public var message: String
    /// Lifts the restriction for THIS session only, and resumes it rather than
    /// restarting — a restart would cost the user everything they were working on,
    /// which made this option look far cheaper than it was.
    public var retryCommand: String

    /// Returns advice only when a restricted host is present AND a worker failed
    /// with one of the known signatures.
    /// - Parameter capacityAuthRequired: true when any seat recorded a typed
    ///   `authRequired` capacity observation. This is the signal to trust: it is a
    ///   classified fact from `CapacityClassifier`, not a string that a vendor can
    ///   reword in its next release. Inside a restricted host it means the sandbox
    ///   blocked sign-in, because the same tools authenticate fine outside it.
    /// True when this process is running inside a host that restricts it.
    ///
    /// On its own this is NEVER grounds to skip a local run: a Codex session
    /// launched with full access carries the same variable and works perfectly.
    /// It is only usable once something has ALREADY failed, to decide whether the
    /// app is worth trying — see the preflight-failure path in `RunCLI`.
    public static func hostIsRestricted(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["CODEX_SANDBOX"] != nil
    }

    public static func detect(
        workerFailureText: [String],
        prompt: String,
        projectReference: String?,
        teamId: String?,
        capacityAuthRequired: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HostSandboxAdvice? {
        guard environment["CODEX_SANDBOX"] != nil else { return nil }
        let matchedText = workerFailureText.contains { text in
            failureSignatures.contains { text.localizedCaseInsensitiveContains($0) }
        }
        guard matchedText || capacityAuthRequired else { return nil }

        return HostSandboxAdvice(
            message: """
            Codex is running in its protected mode, which stops other apps from signing in. \
            Allnighter needs your AI tools to sign in before they can do any work, so this run \
            could not start here. Nothing is wrong with your setup, and nothing was changed.
            """,
            retryCommand: "codex resume --last -c sandbox_mode=\"danger-full-access\""
        )
    }

    /// The whole disclosure as one warning body: what happened, that nothing is
    /// broken, and the ways forward with their blast radius stated.
    ///
    /// This used to open with "Open Allnighter and paste this in: <command>",
    /// written when the hand-off did not exist. It does now — the CLI enqueues the
    /// work and waits — so telling the user to paste the same command by hand
    /// described a product that had been replaced, and contradicted the message
    /// printed moments earlier saying the request had already been handed off.
    public var warningMessage: String {
        """
        \(message)

        Allnighter already handed this to the Mac app, which can start your tools,
        and waited for the answer here. If you are reading this, the app did not
        finish it — the line above this one says what was actually observed.

          1. If Allnighter is not open, open it
             Nothing outside your terminal can start your AI tools while it is
             closed. Then collect this run with:
                 alln run resume <the run id printed above>

          2. Or run it here, in this same session
             Paste this in your terminal:
                 \(retryCommand)
             You pick up exactly where you left off — nothing is lost. It gives
             this one session permission to use your AI tools, changes no
             settings, and Codex is back to normal next time you open it.
        """
    }
}
