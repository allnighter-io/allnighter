import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP projections of `pending list/show/run` — same Core path as CLI.
enum MCPPendingHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func list(runtime: ToolRuntime, args: [String: Any], store: PendingStore? = nil) -> Outcome {
        let service = makeService(runtime, store: store)
        do {
            var items = try service.list()
            if let projectToken = args["project"] as? String, !projectToken.isEmpty {
                let projectStore = ProjectStore()
                guard let project = try projectStore.get(projectToken) else {
                    return .toolError(ErrorEnvelope(
                        code: "PROJECT_NOT_FOUND",
                        message: "project not found: \(projectToken)",
                        requiresManual: true,
                        retryable: false
                    ))
                }
                items = items.filter { $0.projectId == project.id }
            }
            if let status = args["status"] as? String, !status.isEmpty {
                items = items.filter { $0.status.rawValue == status }
            }
            if let cursor = args["cursor"] as? String, !cursor.isEmpty,
               let index = items.firstIndex(where: { $0.id == cursor }) {
                items = Array(items.dropFirst(index + 1))
            }
            if let limit = intArg(args["limit"]) {
                items = Array(items.prefix(max(0, limit)))
            }
            let projections = try items.map { try service.mapJSON($0) }
            let payload = PendingListJSON(contractVersion: ContractRegistry.contractVersion, items: projections)
            let json = AllnighterCLI.jsonString(payload)
            return .success(json, summary: "\(projections.count) pending item(s)")
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    static func show(runtime: ToolRuntime, args: [String: Any], store: PendingStore? = nil) -> Outcome {
        guard let pendingId = args["pendingId"] as? String, !pendingId.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: "pendingId required",
                requiresManual: true,
                retryable: false
            ))
        }
        let service = makeService(runtime, store: store)
        do {
            guard let item = try service.store.load(id: pendingId) else {
                return pendingServiceError(.notFound(pendingId))
            }
            let json = AllnighterCLI.jsonString(try service.mapJSON(item))
            return .success(json, summary: "\(item.id) · \(item.status.rawValue) · \(item.title)")
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    static func run(
        runtime: ToolRuntime,
        args: [String: Any],
        store: PendingStore? = nil,
        commandRunner: CommandRunner? = nil
    ) async -> Outcome {
        guard let pendingId = args["pendingId"] as? String, !pendingId.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: "pendingId required",
                requiresManual: true,
                retryable: false
            ))
        }
        let executor = makeExecutor(runtime, store: store, commandRunner: commandRunner)
        do {
            let item = try await executor.run(id: pendingId)
            let json = AllnighterCLI.jsonString(try executor.service.mapJSON(item))
            let summary = "\(item.id) · \(item.status.rawValue) · \(item.title)"
            _ = args["originAgent"] as? String
            return .success(json, summary: summary)
        } catch let error as PendingServiceError {
            return pendingServiceError(error)
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    // MARK: - Helpers

    static func makeService(_ runtime: ToolRuntime, store: PendingStore? = nil) -> PendingService {
        PendingService(store: store ?? PendingStore(), models: runtime.models)
    }

    static func makeExecutor(
        _ runtime: ToolRuntime,
        store: PendingStore? = nil,
        commandRunner: CommandRunner? = nil
    ) -> PendingRunExecutor {
        let service = makeService(runtime, store: store)
        return PendingRunExecutor(
            service: service,
            registry: runtime.registry,
            commandRunner: commandRunner ?? SubprocessCommandRunner(),
            invocations: runtime.invocations
        )
    }

    private static func pendingServiceError(_ error: PendingServiceError) -> Outcome {
        let envelope: ErrorEnvelope
        switch error {
        case .notFound(let id):
            envelope = ErrorEnvelope(
                code: "RUN_NOT_FOUND",
                message: "pending item not found: \(id)",
                requiresManual: true,
                retryable: false
            )
        case .invalidWorker(let token):
            envelope = ErrorEnvelope(
                code: "MODEL_UNAVAILABLE",
                message: "unknown worker: \(token)",
                requiresManual: true,
                retryable: false
            )
        case .invalidState(let detail):
            envelope = ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: detail,
                requiresManual: true,
                retryable: false
            )
        case .reorderInvalid(let detail):
            envelope = ErrorEnvelope(
                code: "PENDING_REORDER_INVALID",
                message: detail,
                requiresManual: true,
                retryable: false
            )
        case .mutationDeferred:
            envelope = ErrorEnvelope(
                code: "PENDING_MUTATION_DEFERRED",
                message: "mutating dispatch is outside Pending M1",
                requiresManual: true,
                retryable: false
            )
        case .sourceGateBlocked(let blocker):
            envelope = ErrorEnvelope(
                code: blocker.code,
                message: blocker.message,
                requiresManual: true,
                retryable: false
            )
        case .unsupportedKind(let kind):
            envelope = ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: "pending kind \(kind) is not runnable in this milestone; only workerChat is supported",
                requiresManual: true,
                retryable: false
            )
        }
        return .toolError(envelope)
    }

    private static func internalEnvelope(_ error: Error) -> ErrorEnvelope {
        ErrorEnvelope(
            code: "INTERNAL_ERROR",
            message: String(describing: error),
            requiresManual: true,
            retryable: false
        )
    }

    private static func intArg(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as Int64: return Int(n)
        case let n as Double: return Int(n)
        case let s as String: return Int(s)
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }
}
