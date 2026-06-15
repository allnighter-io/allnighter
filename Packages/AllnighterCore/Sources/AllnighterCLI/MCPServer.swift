import Foundation
import AllnighterCore
import AllnighterEngine

/// A minimal MCP stdio server (JSON-RPC 2.0, Content-Length framing) exposing the
/// council as tools any MCP-aware agent (Claude Code, …) can call. Pinned to a
/// named protocol version; unknown majors are reported clearly. Boring deps: a
/// hand-rolled framer, no MCP library.
struct MCPServer {
    let runtime: ToolRuntime
    static let protocolVersion = "2024-11-05"

    func serve() async {
        let reader = FrameReader()
        while let message = reader.next() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any] else { continue }
            let id = obj["id"]
            guard let method = obj["method"] as? String else { continue }
            let params = obj["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                respond(id: id, result: [
                    "protocolVersion": Self.protocolVersion,
                    "serverInfo": ["name": "allnighter", "version": "0.6"],
                    "capabilities": ["tools": [:]]
                ])
            case "tools/list":
                respond(id: id, result: ["tools": toolDefinitions()])
            case "tools/call":
                await handleCall(id: id, params: params)
            case "notifications/initialized", "ping":
                if id != nil { respond(id: id, result: [:]) }
            default:
                if id != nil { respondError(id: id, code: -32601, message: "method not found: \(method)") }
            }
        }
    }

    private func handleCall(id: Any?, params: [String: Any]) async {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let service = runtime.service()
        switch name {
        case "council_ask":
            guard let q = args["question"] as? String else { return respondError(id: id, code: -32602, message: "question required") }
            let req = CouncilRequest(question: q, presetId: args["preset"] as? String, context: args["context"] as? String)
            let result = await service.run(req, origin: .mcp, originAgent: "mcp")
            let text = (result.masterPlan ?? result.estimateNote) + "\n\n[council \(result.preset): \(result.callsSpent) calls]"
            respond(id: id, result: toolText(text, structured: AllnighterCLI.jsonString(result)))
        case "council_presets":
            let summaries = await service.presetSummaries()
            let text = summaries.map { "\($0.id): \($0.name) (~\($0.callPlan.estimatedCalls) calls, \($0.callPlan.quotaRisk))" }.joined(separator: "\n")
            respond(id: id, result: toolText(text))
        case "council_recall":
            let q = args["query"] as? String ?? ""
            let hits = await service.recall(query: q)
            let text = hits.isEmpty ? "(no prior councils match)" : hits.map { "\($0.createdAt) \($0.prompt)" }.joined(separator: "\n")
            respond(id: id, result: toolText(text, structured: AllnighterCLI.jsonString(hits)))
        default:
            respondError(id: id, code: -32602, message: "unknown tool: \(name)")
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            ["name": "council_ask",
             "description": "Run a local multi-model council on a question and return a synthesized master plan + structured analysis. Zero API cost. Use for hard architecture/design decisions.",
             "inputSchema": ["type": "object", "properties": [
                "question": ["type": "string"],
                "preset": ["type": "string", "description": "fast|quality|budget|self_double (optional)"],
                "context": ["type": "string", "description": "optional bounded snippet to consider"]
             ], "required": ["question"]]],
            ["name": "council_presets",
             "description": "List available council presets with a rough call-count estimate.",
             "inputSchema": ["type": "object", "properties": [:]]],
            ["name": "council_recall",
             "description": "Search prior local councils and return past judgments (read-only, zero cost).",
             "inputSchema": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]]]
        ]
    }

    private func toolText(_ text: String, structured: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if let structured { result["structuredContent"] = ["json": structured] }
        return result
    }

    // MARK: - JSON-RPC framing

    private func respond(id: Any?, result: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { msg["id"] = id }
        write(msg)
    }
    private func respondError(id: Any?, code: Int, message: String) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { msg["id"] = id }
        write(msg)
    }
    private func write(_ object: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(body.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(body)
    }
}

/// Reads Content-Length-framed JSON-RPC messages from stdin (blocking).
final class FrameReader {
    private var buffer = Data()
    private let input = FileHandle.standardInput

    func next() -> String? {
        while true {
            if let message = extractFrame() { return message }
            let chunk = input.availableData
            if chunk.isEmpty { return nil } // EOF
            buffer.append(chunk)
        }
    }

    private func extractFrame() -> String? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        let header = String(decoding: headerData, as: UTF8.self)
        var length = 0
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return String(decoding: body, as: UTF8.self)
    }
}
