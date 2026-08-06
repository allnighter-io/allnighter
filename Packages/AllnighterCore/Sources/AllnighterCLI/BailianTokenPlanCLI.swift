import AllnighterCore
import Foundation

/// `alln bailian-token-plan configure | status` — credential setup for the
/// Token Plan Personal (intl) dashboard capacity scrape.
enum BailianTokenPlanCLI {

    static func run(_ args: [String]) {
        let sub = args.first
        let rest = Array(args.dropFirst())
        switch sub {
        case "configure": configure(rest)
        case "status": status(rest)
        default:
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln bailian-token-plan configure [--from-chrome] | echo '<cookie>' | alln bailian-token-plan configure | alln bailian-token-plan status [--json]"
            )
        }
    }

    private static func configure(_ args: [String]) {
        let opts = Options(args)
        let interactive = isatty(STDIN_FILENO) == 1

        let cookie: String
        if opts.flag("from-chrome") {
            cookie = configureFromChrome()
        } else if let flagValue = opts.value("cookie") {
            warn("WARNING: --cookie puts the session token in shell history and process listings. Pipe via stdin or set \(BailianTokenPlanCredentialStore.cookieEnv).")
            cookie = flagValue.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if interactive {
            printSetupInstructions()
            cookie = readSecret(prompt: "Cookie header value: ")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else if let line = Swift.readLine(strippingNewline: true) {
            cookie = line.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "non-interactive stdin with no cookie: pipe value to stdin, pass --cookie, use --from-chrome, or set \(BailianTokenPlanCredentialStore.cookieEnv)",
                suggestions: [
                    "alln bailian-token-plan configure --from-chrome",
                    "echo '<cookie>' | alln bailian-token-plan configure",
                    "alln bailian-token-plan configure --cookie '<cookie>'",
                ]
            )
        }

        guard !cookie.isEmpty else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "cookie header is required. Easiest: alln bailian-token-plan configure --from-chrome (log into Model Studio in Chrome first). Manual: DevTools → Network → usage request → copy the full Cookie header."
            )
        }

        do {
            let url = try BailianTokenPlanCredentialStore.save(
                BailianTokenPlanCredentialStore.Credentials(cookieHeader: cookie)
            )
            print("Saved Bailian Token Plan credentials (encrypted) → \(url.path)")
            print("Next: alln bailian-token-plan status")
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not save credentials: \(error)"
            )
        }
    }

    struct StatusJSON: Encodable {
        let configured: Bool
        let credentialSource: String?
        let error: String?
    }

    private static func status(_ args: [String]) {
        let opts = Options(args)
        let resolved = BailianTokenPlanCredentialStore.load()

        let payload: StatusJSON
        switch resolved {
        case .success(let value):
            payload = StatusJSON(
                configured: true,
                credentialSource: value.source.rawValue,
                error: nil
            )
        case .failure(let error):
            payload = StatusJSON(
                configured: false,
                credentialSource: nil,
                error: describe(error)
            )
        }

        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
            return
        }
        if payload.configured {
            print("Bailian Token Plan capacity: configured")
            print("Credential: \(payload.credentialSource ?? "-")")
        } else {
            print("Bailian Token Plan capacity: not usable — \(payload.error ?? "unknown")")
            print("Fix: alln bailian-token-plan configure --from-chrome")
        }
        print("Dogfood meter: alln capacity --dogfood --source \(CapacityAcquisition.bailianTokenPlanSourceId)")
    }

    static func describe(_ error: BailianTokenPlanCredentialStore.LoadError) -> String {
        switch error {
        case .notConfigured, .missingCookie:
            return "not configured"
        case .decryptFailed:
            return "stored credential could not be decrypted (rotated or corrupt machine key) — re-run configure"
        }
    }

    private static func printSetupInstructions() {
        let text = """
        You need the full Cookie header, not one cookie from Application.

          EASIEST  alln bailian-token-plan configure --from-chrome
                   (log into Model Studio in Chrome first)

          MANUAL   DevTools → Network → reload Token Plan page:
                   https://modelstudio.console.alibabacloud.com/ap-southeast-1?tab=plan#/efm/subscription/token-plan/personal
                   Click the `usage` request to bailian-singapore-cs.alibabacloud.com
                   Copy Request Headers → Cookie (entire value, many name=value pairs)

        """
        FileHandle.standardError.write(Data(text.utf8))
    }

    private static func configureFromChrome() -> String {
        do {
            let imported = try BailianTokenPlanChromeCookieImporter.importWithDisclosure { disclosure in
                FileHandle.standardError.write(Data(disclosure.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
            }
            return imported.cookieHeader
        } catch BailianTokenPlanChromeCookieImporter.ImportError.chromeNotFound {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "Chrome not found. Log into Model Studio in Chrome, or paste the Cookie header manually:\n  pbpaste | alln bailian-token-plan configure"
            )
        } catch BailianTokenPlanChromeCookieImporter.ImportError.cookieNotFound {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: """
                No Alibaba Cloud login cookies found in Chrome.

                Log in here in Chrome first:
                  https://modelstudio.console.alibabacloud.com/ap-southeast-1?tab=plan#/efm/subscription/token-plan/personal

                Then re-run:
                  alln bailian-token-plan configure --from-chrome
                """
            )
        } catch BailianTokenPlanChromeCookieImporter.ImportError.keychainDenied {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "Keychain access was denied, so Chrome cookies cannot be decrypted.\nRe-run and choose Always Allow, or paste manually:\n  pbpaste | alln bailian-token-plan configure"
            )
        } catch BailianTokenPlanChromeCookieImporter.ImportError.emptyCookieHeader {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "Chrome cookies were found but none matched the Token Plan quota host.\nReload the subscription page in Chrome, then re-run --from-chrome."
            )
        } catch BailianTokenPlanChromeCookieImporter.ImportError.notAuthenticated {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "Chrome cookies were found but no login session was detected.\nLog into Model Studio in Chrome, then re-run --from-chrome."
            )
        } catch {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "could not import Chrome cookies: \(error)"
            )
        }
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }

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
