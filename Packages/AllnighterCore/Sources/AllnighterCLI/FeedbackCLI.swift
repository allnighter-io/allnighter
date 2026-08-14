import Foundation
import AllnighterCore

/// `alln feedback "<message>"` — postcard to a person. Nothing but the quoted
/// text, CLI version, and OS leaves the machine.
enum FeedbackCLI {
    static func run(_ args: [String]) async {
        let opts = Options(args)
        let message = opts.positional.joined(separator: " ")
        let dryRun = opts.flag("dry-run")
        let service = FeedbackService.standard
        let result: Result<FeedbackJSON, FeedbackError>
        if dryRun {
            result = service.preview(message: message)
        } else {
            result = await service.send(message: message)
        }
        switch result {
        case .success(let json):
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(json))
                return
            }
            print("Leaving this machine:")
            print("  message: \(json.payload.message)")
            print("  binaryVersion: \(json.payload.binaryVersion)")
            print("  os: \(json.payload.os)")
            print("")
            print(json.tellHuman)
        case .failure(let error):
            fail(error)
        }
    }

    private static func fail(_ error: FeedbackError) -> Never {
        switch error {
        case .empty:
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "usage: alln feedback \"<your message>\" [--dry-run] [--json]"
            )
        case .tooLong(let limit):
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "message must be \(limit) characters or fewer"
            )
        case .rateLimited(let limit):
            AllnighterCLI.fail(
                code: "FEEDBACK_RATE_LIMITED",
                message: "already sent \(limit) messages today. Email \(SupportHatch.email) — a person reads it."
            )
        case .unavailable:
            AllnighterCLI.fail(
                code: "FEEDBACK_UNAVAILABLE",
                message: SupportHatch.tellHuman
            )
        case .rejected(let detail):
            AllnighterCLI.fail(
                code: "FEEDBACK_REJECTED",
                message: "feedback was not accepted. \(SupportHatch.tellHuman)\(detail.isEmpty ? "" : " (\(detail.prefix(120)))")"
            )
        }
    }
}
