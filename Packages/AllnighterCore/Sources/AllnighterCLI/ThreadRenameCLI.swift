import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln thread rename <thread-id|latest> "<title>"` — the CLI/agent surface for the same
/// rename the inbox sidebar uses (double-click). Goes through the one SSOT, ThreadStore.
enum ThreadRenameCLI {
    static func runRename(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let threadRef = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "usage: alln thread rename <thread-id|latest> \"<title>\" [--json]")
        }
        let title = opts.value("title") ?? opts.positional.dropFirst().joined(separator: " ")
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "a non-empty title is required")
        }

        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
        }

        do {
            let thread = try store.renameThread(threadId: threadId, title: title)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(thread))
            } else {
                print("renamed \(thread.id) → \(thread.title)")
            }
        } catch let error as ThreadStoreError {
            switch error {
            case .threadNotFound:
                AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadId)")
            case .emptyTitle:
                AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "a non-empty title is required")
            default:
                AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "\(error)")
        }
    }
}
