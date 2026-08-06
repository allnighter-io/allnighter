import AllnighterCore
import Foundation

/// `alln opencode-go configure | status` — credential setup for the Go
/// dashboard capacity scrape.
///
/// Separate from `alln capacity` on purpose: capacity *reads* a meter, this
/// *owns the secret*. Keeping the cookie-handling surface in one small file
/// makes "never print the cookie" auditable in one place.
enum OpenCodeGoCLI {

    static func run(_ args: [String]) {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "configure": configure(rest)
        case "status": status(rest)
        default:
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln opencode-go configure [--workspace-id <wrk_…>] [--cookie <auth>] | alln opencode-go status [--json]"
            )
        }
    }

    // MARK: - configure

    private static func configure(_ args: [String]) {
        let opts = Options(args)
        let workspaceId = (opts.value("workspace-id") ?? readLine(prompt: "Workspace ID (wrk_…): "))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cookie = (opts.value("cookie") ?? readSecret(prompt: "Auth cookie value: "))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !workspaceId.isEmpty else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "workspace id is required. Find it in the dashboard URL: opencode.ai/workspace/<wrk_…>/go"
            )
        }
        guard !cookie.isEmpty else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "auth cookie is required. In a logged-in browser: DevTools → Application → Cookies → copy the `auth` value."
            )
        }
        // Advisory only — the owner's input wins. A future id format must not
        // lock the owner out of their own workspace over a prefix check.
        if !workspaceId.hasPrefix("wrk_") {
            warn("workspace id does not start with `wrk_` — saving it anyway, but check the dashboard URL if the scrape fails.")
        }

        do {
            let url = try OpenCodeGoCredentialStore.save(
                OpenCodeGoCredentialStore.Credentials(workspaceId: workspaceId, authCookie: cookie)
            )
            // Deliberately echoes the workspace id (public, it is in the URL)
            // and never the cookie.
            print("Saved OpenCode Go credentials (encrypted) → \(url.path)")
            print("Workspace: \(workspaceId)")
            print("Next: alln opencode-go status")
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not save credentials: \(error)"
            )
        }
    }

    // MARK: - status

    struct StatusJSON: Encodable {
        let configured: Bool
        let workspaceId: String?
        let credentialSource: String?
        let error: String?
    }

    private static func status(_ args: [String]) {
        let opts = Options(args)
        let resolved = OpenCodeGoCredentialStore.load()

        let payload: StatusJSON
        switch resolved {
        case .success(let value):
            payload = StatusJSON(
                configured: true,
                workspaceId: value.credentials.workspaceId,
                credentialSource: value.source.rawValue,
                error: nil
            )
        case .failure(let error):
            payload = StatusJSON(
                configured: false,
                workspaceId: nil,
                credentialSource: nil,
                error: describe(error)
            )
        }

        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
            return
        }
        if payload.configured {
            print("OpenCode Go capacity: configured")
            print("Workspace: \(payload.workspaceId ?? "-")")
            print("Credential: \(payload.credentialSource ?? "-")")
        } else {
            print("OpenCode Go capacity: not usable — \(payload.error ?? "unknown")")
            print("Fix: alln opencode-go configure")
        }
        print("Meter: alln capacity --dogfood --refresh --source opencode_go")
    }

    /// Recovery-oriented, and careful to keep "never configured" distinct from
    /// "configured but unusable" — they need different actions from the owner.
    static func describe(_ error: OpenCodeGoCredentialStore.LoadError) -> String {
        switch error {
        case .notConfigured, .missingWorkspaceId, .missingAuthCookie:
            return "not configured"
        case .partialEnvironment:
            return "only one of \(OpenCodeGoCredentialStore.workspaceIdEnv) / \(OpenCodeGoCredentialStore.authCookieEnv) is set — set both or neither"
        case .decryptFailed:
            return "stored credential could not be decrypted (rotated or corrupt machine key) — re-run configure"
        }
    }

    // MARK: - Input

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }

    private static func readLine(prompt: String) -> String? {
        FileHandle.standardError.write(Data(prompt.utf8))
        return Swift.readLine(strippingNewline: true)
    }

    /// Reads without echoing so the cookie never lands on screen. Falls back to
    /// a visible read only when there is no TTY (piped/automated input), where
    /// there is nothing to hide it from.
    private static func readSecret(prompt: String) -> String? {
        guard isatty(STDIN_FILENO) == 1 else { return Swift.readLine(strippingNewline: true) }
        FileHandle.standardError.write(Data(prompt.utf8))
        var term = termios()
        tcgetattr(STDIN_FILENO, &term)
        var quiet = term
        quiet.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &quiet)
        defer {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &term)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return Swift.readLine(strippingNewline: true)
    }
}
