import Foundation
import AllnighterCore
import AllnighterEngine

enum ThreadCLI {
    static func runGet(_ args: [String]) {
        let opts = Options(args)
        guard let threadRef = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "usage: alln thread get <thread-id|latest> [--json]")
        }

        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store),
              let thread = store.get(threadId) else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
        }

        let projection = project(thread: thread, threadId: threadId, store: store)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(projection))
        } else {
            print("\(projection.title) · \(projection.turns.count) turns")
        }
    }

    static func runStatus(_ args: [String]) {
        let opts = Options(args)
        guard let threadRef = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "usage: alln thread status <thread-id|latest> [--json]")
        }

        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store),
              let thread = store.get(threadId) else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
        }

        let status = ThreadStatusResponse(
            threadId: threadId,
            isRunning: thread.isRunning,
            needsAttention: thread.needsAttention
        )
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(status))
        } else {
            print(thread.isRunning ? "running" : (thread.needsAttention ? "needs attention" : "idle"))
        }
    }

    static func runAttachmentGet(_ args: [String]) {
        let opts = Options(args)
        guard let threadRef = opts.positional.first,
              let attachmentId = opts.positional.dropFirst().first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR",
                               message: "usage: alln thread attachment <thread-id|latest> <attachment-id> [--json]")
        }

        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
        }

        do {
            let dir = try store.threadDirectory(forThreadId: threadId)
            guard let response = ThreadAttachmentResolver.attachmentGet(
                threadId: threadId, attachmentId: attachmentId, threadDirectory: dir
            ) else {
                AllnighterCLI.fail(code: "ATTACHMENT_NOT_FOUND", message: "attachment not found: \(attachmentId)")
            }
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(response))
            } else {
                print(response.canonicalPath)
            }
        } catch {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "\(error)")
        }
    }

    static func project(thread: WorkThread, threadId: String, store: ThreadStore) -> ThreadGetResponse {
        let dir = (try? store.threadDirectory(forThreadId: threadId))
            ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
        return ThreadAttachmentResolver.project(
            thread: thread,
            threadDirectory: dir,
            contractVersion: ContractRegistry.contractVersion
        )
    }
}
