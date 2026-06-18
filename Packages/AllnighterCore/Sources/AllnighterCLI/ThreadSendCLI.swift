import Foundation
import AllnighterCore
import AllnighterEngine
import CryptoKit

enum ThreadSendCLI {
    struct Response: Codable {
        var threadId: String
        var userTurnId: String
        var workerTurnId: String
        var attachmentIds: [String]
        var attachments: [AttachmentRow]
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
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln thread send <thread-id|latest> [<message>] [--image path]... [--worker id] [--idempotency-key key] [--json]")
        }
        let message = opts.positional.dropFirst().joined(separator: " ")
        let images = collectImagePaths(from: args)
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "requires at least one of message or --image")
        }

        let store = ThreadStore()
        let threadId: String
        if threadRef == "latest" {
            guard let latest = store.list().first else {
                AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "no threads exist")
            }
            threadId = latest.id
        } else {
            threadId = threadRef
        }
        guard store.get(threadId) != nil else {
            AllnighterCLI.fail(code: "THREAD_NOT_FOUND", message: "thread not found: \(threadId)")
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

        let workerId = opts.value("worker")
        let canonical = ThreadSendCanonicalPayload(threadId: threadId, message: message, workerId: workerId, imageHashes: imageHashes)
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
            commandRunner: SubprocessCommandRunner(),
            invocations: runtime.invocations,
            registry: runtime.registry,
            models: runtime.readyModels,
            defaultDriverWorkerId: runtime.models.first?.id
        )

        do {
            let result = try await coordinator.send(
                request: ThreadSendCoordinator.Request(message: message, images: frozenInputs, requestedWorkerId: workerId),
                toThreadId: threadId
            )
            if let key = opts.value("idempotency-key"), !key.isEmpty {
                try? idempotency.record(
                    key: key, payload: canonical,
                    userTurnId: result.userTurnId, workerTurnId: result.workerTurnId,
                    workerAttachmentIds: result.workerAttachmentIds.isEmpty ? nil : result.workerAttachmentIds
                )
            }
            if opts.flag("json") {
                let response = Response(
                    threadId: threadId,
                    userTurnId: result.userTurnId,
                    workerTurnId: result.workerTurnId,
                    attachmentIds: result.attachmentIds,
                    attachments: result.deliveries.map { row(from: $0) },
                    workerAttachmentIds: result.workerAttachmentIds,
                    workerAttachments: result.workerDeliveries.map { row(from: $0) }
                )
                print(AllnighterCLI.jsonString(response))
            } else {
                print("sent to \(result.workerId): user=\(result.userTurnId) worker=\(result.workerTurnId) attachments=\(result.attachmentIds.count) workerImages=\(result.workerAttachmentIds.count)")
            }
        } catch let error as AttachmentError {
            AllnighterCLI.fail(code: error.code, message: error.description)
        } catch let error as WorkerChatCoordinator.ChatError {
            AllnighterCLI.fail(code: "WORKER_FAILED", message: error.description)
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
            workerAttachmentIds: workerIds,
            workerAttachments: []
        )
        print(AllnighterCLI.jsonString(response))
    }
}

enum MCPThreadSendHandlers {
    enum SendOutcome {
        case success(Response)
        case failure(ErrorEnvelope)
    }

    static func parseImages(_ raw: Any?) -> [(path: String?, base64: String?, mime: String?)] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { item in
            if let path = item as? String { return (path, nil, nil) }
            if let obj = item as? [String: Any] {
                return (nil, obj["base64"] as? String, obj["mimeType"] as? String)
            }
            return nil
        }
    }

    static func runSend(args: [String: Any], runtime: ToolRuntime) async -> SendOutcome {
        let threadRef = (args["threadId"] as? String) ?? "latest"
        let message = (args["message"] as? String) ?? ""
        let workerId = args["workerId"] as? String
        let idempotencyKey = args["idempotencyKey"] as? String
        let images = parseImages(args["images"])

        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            return .failure(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "requires message or images", requiresManual: true, retryable: false))
        }

        let store = ThreadStore()
        let threadId: String
        if threadRef == "latest" {
            guard let latest = store.list().first else {
                return .failure(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "no threads exist", requiresManual: true, retryable: false))
            }
            threadId = latest.id
        } else {
            threadId = threadRef
        }
        guard store.get(threadId) != nil else {
            return .failure(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "thread not found", requiresManual: true, retryable: false))
        }

        var frozenInputs: [ThreadSendCoordinator.ImageInput] = []
        var imageHashes: [String] = []
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("alln-mcp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let ingestor = AttachmentIngestor()
        for (index, image) in images.enumerated() {
            do {
                let ingested: IngestedAttachment
                let kind: AttachmentSourceKind
                if let path = image.path {
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        return .failure(ErrorEnvelope(code: "ATTACHMENT_DECODE_FAILED", message: "unreadable path", requiresManual: true, retryable: false))
                    }
                    let data = try Data(contentsOf: url)
                    imageHashes.append(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                    ingested = try ingestor.ingest(data: data, declaredMIME: nil, sourceKind: .mcpPath, originalName: url.lastPathComponent)
                    kind = .mcpPath
                } else if let base64 = image.base64 {
                    ingested = try ingestor.ingestBase64(base64, declaredMIME: image.mime, sourceKind: .mcpBase64)
                    imageHashes.append(ingested.storedSha256)
                    kind = .mcpBase64
                } else {
                    return .failure(ErrorEnvelope(code: "ATTACHMENT_BASE64_INVALID", message: "invalid image item", requiresManual: true, retryable: false))
                }
                let frozen = tempRoot.appendingPathComponent("img\(index).png")
                try ingested.pngData.write(to: frozen)
                frozenInputs.append(ThreadSendCoordinator.ImageInput(frozenFileURL: frozen, sourceKind: kind, originalName: nil, sourceSha256: ingested.sourceSha256))
            } catch let error as AttachmentError {
                return .failure(ErrorEnvelope(code: error.code, message: error.description, requiresManual: true, retryable: false))
            } catch {
                return .failure(ErrorEnvelope(code: "ATTACHMENT_DECODE_FAILED", message: error.localizedDescription, requiresManual: true, retryable: false))
            }
        }

        let canonical = ThreadSendCanonicalPayload(threadId: threadId, message: message, workerId: workerId, imageHashes: imageHashes)
        let idempotency = ThreadSendIdempotencyStore()
        if let key = idempotencyKey, !key.isEmpty {
            switch idempotency.lookup(key: key, payload: canonical) {
            case .hit(let entry):
                let store = ThreadStore()
                let thread = store.get(threadId)
                let userTurn = thread?.turns.first { $0.id == entry.userTurnId }
                let workerTurn = thread?.turns.first { $0.id == entry.workerTurnId }
                let workerIds = entry.workerAttachmentIds ?? workerTurn?.attachmentRefs.map(\.attachmentId) ?? []
                return .success(Response(
                    threadId: threadId,
                    userTurnId: entry.userTurnId,
                    workerTurnId: entry.workerTurnId,
                    attachmentIds: userTurn?.attachmentRefs.map(\.attachmentId) ?? [],
                    deliveries: [],
                    workerAttachmentIds: workerIds,
                    workerDeliveries: []
                ))
            case .conflict:
                return .failure(ErrorEnvelope(code: "THREAD_SEND_IDEMPOTENCY_CONFLICT", message: "idempotency conflict", requiresManual: false, retryable: false))
            case .miss:
                break
            }
        }

        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: SubprocessCommandRunner(),
            invocations: runtime.invocations,
            registry: runtime.registry,
            models: runtime.readyModels
        )
        do {
            let result = try await coordinator.send(
                request: ThreadSendCoordinator.Request(message: message, images: frozenInputs, requestedWorkerId: workerId),
                toThreadId: threadId
            )
            if let key = idempotencyKey, !key.isEmpty {
                try? idempotency.record(
                    key: key, payload: canonical,
                    userTurnId: result.userTurnId, workerTurnId: result.workerTurnId,
                    workerAttachmentIds: result.workerAttachmentIds.isEmpty ? nil : result.workerAttachmentIds
                )
            }
            return .success(Response(
                threadId: threadId,
                userTurnId: result.userTurnId,
                workerTurnId: result.workerTurnId,
                attachmentIds: result.attachmentIds,
                deliveries: result.deliveries,
                workerAttachmentIds: result.workerAttachmentIds,
                workerDeliveries: result.workerDeliveries
            ))
        } catch let error as AttachmentError {
            return .failure(ErrorEnvelope(code: error.code, message: error.description, requiresManual: true, retryable: false))
        } catch let error as WorkerChatCoordinator.ChatError {
            return .failure(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: error.description, requiresManual: true, retryable: false))
        } catch {
            return .failure(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: error.localizedDescription, requiresManual: true, retryable: false))
        }
    }

    struct Response: Codable {
        var threadId: String
        var userTurnId: String
        var workerTurnId: String
        var attachmentIds: [String]
        var deliveries: [IncludedAttachmentDelivery]
        var workerAttachmentIds: [String]
        var workerDeliveries: [IncludedAttachmentDelivery]
    }
}
