import Foundation
import AllnighterCore
import AllnighterEngine
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum ThreadSendCLI {
    struct Response: Codable {
        var threadId: String
        var userTurnId: String
        var workerTurnId: String
        var attachmentIds: [String]
        var attachments: [AttachmentRow]
        var fileReferenceIds: [String]
        var fileReferences: [IncludedFileReferenceDelivery]
        var workerAttachmentIds: [String]
        var workerAttachments: [AttachmentRow]

        struct AttachmentRow: Codable {
            var attachmentId: String
            var canonicalPath: String
            var deliveredPathUsed: String
            var storedSha256: String
        }
    }

    static func runSend(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let threadRef = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln thread send <thread-id|latest> [<message>] [--image path]... [--ref path[:start-end]]... [--model id] [--idempotency-key key] [--json]")
        }
        let message = opts.positional.dropFirst().joined(separator: " ")
        let images = collectImagePaths(from: args)
        let fileReferences = collectFileReferences(from: args)
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty || !fileReferences.isEmpty else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "requires at least one of message, --image, or --ref")
        }

        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
        }

        var frozenInputs: [ThreadSendCoordinator.ImageInput] = []
        var imageHashes: [String] = []
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("alln-freeze-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for (index, path) in images.enumerated() {
            let source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else {
                AllnighterCLI.fail(code: "ATTACHMENT_DECODE_FAILED", message: "file unreadable: \(path)")
            }
            let data = (try? Data(contentsOf: source)) ?? Data()
            imageHashes.append(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            let frozen = tempRoot.appendingPathComponent("img\(index).png")
            try? data.write(to: frozen)
            frozenInputs.append(ThreadSendCoordinator.ImageInput(
                frozenFileURL: frozen, sourceKind: .cliFile, originalName: source.lastPathComponent, sourceSha256: imageHashes.last
            ))
        }

        let workerId = opts.value("model")
        AllnighterCLI.requireExactSelectors(
            workerId: workerId,
            teamId: nil,
            models: runtime.models,
            teams: runtime.teams
        )
        let canonical = ThreadSendCanonicalPayload(
            threadId: threadId,
            message: message,
            workerId: workerId,
            imageHashes: imageHashes,
            fileReferences: fileReferences
        )
        let idempotency = ThreadSendIdempotencyStore()
        if let key = opts.value("idempotency-key"), !key.isEmpty {
            switch idempotency.lookup(key: key, payload: canonical) {
            case .hit(let entry):
                if opts.flag("json") {
                    emitCachedJSON(threadId: threadId, entry: entry, store: store)
                } else {
                    print("idempotent replay: userTurn=\(entry.userTurnId) workerTurn=\(entry.workerTurnId)")
                }
                return
            case .conflict:
                AllnighterCLI.fail(code: "THREAD_SEND_IDEMPOTENCY_CONFLICT", message: "idempotency key reused with different payload")
            case .miss:
                break
            }
        }

        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
            invocations: runtime.invocations,
            registry: runtime.registry,
            models: runtime.readyModels,
            defaultDriverWorkerId: runtime.models.first?.id
        )

        do {
            let result = try await coordinator.send(
                request: ThreadSendCoordinator.Request(
                    message: message,
                    images: frozenInputs,
                    fileReferences: fileReferences,
                    requestedWorkerId: workerId
                ),
                toThreadId: threadId
            )
            if let key = opts.value("idempotency-key"), !key.isEmpty {
                try? idempotency.record(
                    key: key, payload: canonical,
                    userTurnId: result.userTurnId, workerTurnId: result.workerTurnId,
                    workerAttachmentIds: result.workerAttachmentIds.isEmpty ? nil : result.workerAttachmentIds,
                    fileReferenceIds: result.fileReferenceIds.isEmpty ? nil : result.fileReferenceIds
                )
            }
            if opts.flag("json") {
                let response = Response(
                    threadId: threadId,
                    userTurnId: result.userTurnId,
                    workerTurnId: result.workerTurnId,
                    attachmentIds: result.attachmentIds,
                    attachments: result.deliveries.map { row(from: $0) },
                    fileReferenceIds: result.fileReferenceIds,
                    fileReferences: result.fileReferences,
                    workerAttachmentIds: result.workerAttachmentIds,
                    workerAttachments: result.workerDeliveries.map { row(from: $0) }
                )
                print(AllnighterCLI.jsonString(response))
            } else {
                print("sent to \(result.workerId): user=\(result.userTurnId) worker=\(result.workerTurnId) attachments=\(result.attachmentIds.count) fileRefs=\(result.fileReferenceIds.count) workerImages=\(result.workerAttachmentIds.count)")
            }
        } catch let error as AttachmentError {
            AllnighterCLI.fail(code: error.code, message: error.description)
        } catch let error as FileReferenceError {
            AllnighterCLI.fail(code: error.code, message: error.description)
        } catch let error as WorkerChatCoordinator.ChatError {
            AllnighterCLI.fail(code: "AGENT_FAILED", message: error.description)
        } catch {
            AllnighterCLI.fail(code: "THREAD_SEND_FAILED", message: error.localizedDescription)
        }
    }

    private static func collectImagePaths(from args: [String]) -> [String] {
        var paths: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--image", i + 1 < args.count {
                paths.append(args[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return paths
    }

    private static func collectFileReferences(from args: [String]) -> [FileReferenceInput] {
        var refs: [FileReferenceInput] = []
        var i = 0
        while i < args.count {
            if args[i] == "--ref", i + 1 < args.count {
                if let parsed = FileReferenceTokenParser.parseSpecifier(args[i + 1]) {
                    refs.append(parsed)
                }
                i += 2
            } else {
                i += 1
            }
        }
        return refs.dedupedPreservingOrder()
    }

    private static func row(from delivery: IncludedAttachmentDelivery) -> Response.AttachmentRow {
        Response.AttachmentRow(
            attachmentId: delivery.attachmentId,
            canonicalPath: delivery.canonicalPath,
            deliveredPathUsed: delivery.deliveredPathUsed,
            storedSha256: delivery.storedSha256
        )
    }

    private static func emitCachedJSON(threadId: String, entry: ThreadSendIdempotencyStore.Entry, store: ThreadStore) {
        let thread = store.get(threadId)
        let userTurn = thread?.turns.first { $0.id == entry.userTurnId }
        let workerTurn = thread?.turns.first { $0.id == entry.workerTurnId }
        let workerIds = entry.workerAttachmentIds ?? workerTurn?.attachmentRefs.map(\.attachmentId) ?? []
        let response = Response(
            threadId: threadId,
            userTurnId: entry.userTurnId,
            workerTurnId: entry.workerTurnId,
            attachmentIds: userTurn?.attachmentRefs.map(\.attachmentId) ?? [],
            attachments: [],
            fileReferenceIds: entry.fileReferenceIds ?? userTurn?.fileReferenceRefs.map(\.referenceId) ?? [],
            fileReferences: [],
            workerAttachmentIds: workerIds,
            workerAttachments: []
        )
        print(AllnighterCLI.jsonString(response))
    }
}
