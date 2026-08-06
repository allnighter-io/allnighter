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
                message: "usage: echo '<cookie>' | alln opencode-go configure --workspace-id <wrk_…> | alln opencode-go status [--json]"
            )
        }
    }

    // MARK: - configure

    private static func configure(_ args: [String]) {
        let opts = Options(args)
        let interactive = isatty(STDIN_FILENO) == 1

        // The machine usually already knows the workspace — the OpenCode CLI
        // stores it. Ask only when discovery is ambiguous or comes up empty.
        let discovered = OpenCodeGoCredentialStore.discoverWorkspaceId()
        if !interactive, opts.value("workspace-id") == nil, discovered == nil {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "non-interactive stdin and no workspace id found in local OpenCode state: pass --workspace-id",
                suggestions: ["alln opencode-go configure --workspace-id <wrk_…>"]
            )
        }
        let workspaceId: String
        if let explicit = opts.value("workspace-id") {
            workspaceId = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let discovered {
            warn("using workspace \(discovered) discovered from local OpenCode state — pass --workspace-id to override")
            workspaceId = discovered
        } else {
            workspaceId = readLine(prompt: "Workspace ID (wrk_…): ")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let cookie: String
        if opts.flag("from-chrome") {
            if opts.value("cookie") != nil {
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "--from-chrome and --cookie are mutually exclusive — the whole point of --from-chrome is to never hand-paste a cookie"
                )
            }
            cookie = configureFromChrome()
        } else if let flagValue = opts.value("cookie") {
            warn("WARNING: --cookie puts the session token in shell history and process listings. Pipe via stdin or set \(OpenCodeGoCredentialStore.authCookieEnv).")
            cookie = flagValue.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if interactive {
            cookie = readSecret(prompt: "Auth cookie value: ")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else if let line = Swift.readLine(strippingNewline: true) {
            cookie = line.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "non-interactive stdin with no cookie: pipe value to stdin, pass --cookie, or set \(OpenCodeGoCredentialStore.authCookieEnv)",
                suggestions: [
                    "echo '<cookie>' | alln opencode-go configure --workspace-id <wrk_…>",
                    "alln opencode-go configure --workspace-id <wrk_…> --cookie <auth>",
                    "alln opencode-go configure --from-chrome --workspace-id <wrk_…>"
                ]
            )
        }

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
        // --dogfood was retired for this source at promotion (OCG-S08); the seat
        // is a normal bench member now. Teaching the dead flag here would send
        // the owner to a gate that no longer exists.
        print("Meter: alln capacity --refresh --source opencode_go")
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

    /// Finds the auth cookie in Chrome, prints a disclosure, reads the keychain,
    /// decrypts the cookie, and returns it. Disclosure is printed BEFORE keychain
    /// access — this ordering is the whole point of the slice.
    private static func configureFromChrome() -> String {
        let (profileName, encrypted): (String, Data)
        do {
            (profileName, encrypted) = try OpenCodeGoChromeCookieImporter.findCookie(
                chromeRoot: OpenCodeGoChromeCookieImporter.defaultChromeRoot,
                fileManager: .default
            )
        } catch let error as OpenCodeGoChromeCookieImporter.ImportError {
            switch error {
            case .chromeNotFound:
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "Chrome not found. If you use Safari or Firefox, tell Fable — those store cookie values in plaintext and need a different reader."
                )
            case .cookieNotFound:
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "No opencode.ai 'auth' cookie in any Chrome profile.\nLog in at https://opencode.ai in Chrome, then re-run:\n  alln opencode-go configure --from-chrome"
                )
            default:
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "could not read Chrome cookies: \(error)"
                )
            }
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not read Chrome cookies: \(error)"
            )
        }

        // Disclosure before the prompt — required by founder ruling 2026-08-06.
        let disclosure = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: profileName)
        FileHandle.standardError.write(Data(disclosure.utf8))
        FileHandle.standardError.write(Data("\n".utf8))

        let password: String
        do {
            password = try OpenCodeGoChromeCookieImporter.readKeychainPassword()
        } catch OpenCodeGoChromeCookieImporter.ImportError.keychainDenied {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "Keychain access was denied, so the cookie cannot be decrypted.\nRe-run and choose Always Allow, or paste manually:\n  pbpaste | alln opencode-go configure"
            )
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not access keychain: \(error)"
            )
        }

        let key = OpenCodeGoChromeCookieImporter.deriveKey(password: password)
        let cookie: String
        do {
            cookie = try OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        } catch OpenCodeGoChromeCookieImporter.ImportError.unexpectedPrefix(let prefix) {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "unexpected Chrome cookie encryption prefix \(prefix) — Chrome may have changed its format. Try manually:\n  pbpaste | alln opencode-go configure"
            )
        } catch OpenCodeGoChromeCookieImporter.ImportError.decryptionFailed {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not decrypt the Chrome cookie — the key or format may have changed. Try manually:\n  pbpaste | alln opencode-go configure"
            )
        } catch OpenCodeGoChromeCookieImporter.ImportError.emptyCookie {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "decrypted Chrome cookie was empty — the session may be expired. Log in at https://opencode.ai in Chrome and try again."
            )
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not decrypt Chrome cookie: \(error)"
            )
        }
        return cookie
    }
}
