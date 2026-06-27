import Foundation
import AllnighterCore

/// Parses OpenCode serve `GET /event` SSE `data: {…}` lines into worker stream
/// events. Event JSON shape: `{ "type": "...", "properties": {…} }`.
public final class OpenCodeSSEParser: @unchecked Sendable {
    private var buffer = ""
    private var answerAccumulator = ""
    private var reasoningAccumulator = ""
    private var answerSeq = 0
    private var reasoningSeq = 0
    /// Distinct tool calls seen this turn (keyed by `callID`). A non-empty set means the
    /// model did real work via tools (wrote files / ran commands) even if it emitted no
    /// visible answer text — the basis for distinguishing a *tool-only completion* (success)
    /// from a genuinely empty turn.
    private var toolCallIDs: Set<String> = []
    /// First `session.error` reason seen this turn, if any. A turn that errored is a failure
    /// regardless of tool activity.
    private var firstSessionError: String?

    public init() {}

    /// Feed raw SSE bytes; returns zero or more stream events for this chunk.
    public func receive(_ data: Data) -> [WorkerStreamEvent] {
        buffer += String(decoding: data, as: UTF8.self)
        var events: [WorkerStreamEvent] = []
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            events.append(contentsOf: handleBlock(block))
        }
        // Also handle single-newline framed `data:` lines (common in fixtures).
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex..<buffer.index(after: newline))
            if line.hasPrefix("data:") {
                events.append(contentsOf: handleDataLine(line))
            }
        }
        return events
    }

    /// Drain any trailing partial block at stream end.
    public func flush() -> [WorkerStreamEvent] {
        guard !buffer.isEmpty else { return [] }
        let tail = buffer
        buffer = ""
        return handleBlock(tail)
    }

    public var accumulatedAnswer: String { answerAccumulator }
    public var accumulatedReasoning: String { reasoningAccumulator }
    /// Count of distinct tool calls this turn. `> 0` ⇒ the model performed tool work.
    public var toolActionCount: Int { toolCallIDs.count }
    /// The first `session.error` reason this turn, or nil if the turn never errored.
    public var sessionError: String? { firstSessionError }

    private func handleBlock(_ block: String) -> [WorkerStreamEvent] {
        block.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("data:") }
            .flatMap(handleDataLine)
    }

    private func handleDataLine(_ line: String) -> [WorkerStreamEvent] {
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return [] }
        let properties = obj["properties"] as? [String: Any] ?? [:]

        switch type {
        case "message.part.updated", "message.part.delta":
            return partEvents(properties: properties, raw: String(payload))
        case "session.error":
            if firstSessionError == nil {
                firstSessionError = Self.errorReason(properties) ?? "unknown session error"
            }
            return [.rawEvent(sourceId: "opencode", json: String(payload))]
        case "session.idle":
            return [.rawEvent(sourceId: "opencode", json: String(payload))]
        case "session.status":
            if (properties["status"] as? String) == "idle" {
                return [.rawEvent(sourceId: "opencode", json: String(payload))]
            }
            return [.rawEvent(sourceId: "opencode", json: String(payload))]
        default:
            return [.rawEvent(sourceId: "opencode", json: String(payload))]
        }
    }

    private func partEvents(properties: [String: Any], raw: String) -> [WorkerStreamEvent] {
        guard let part = properties["part"] as? [String: Any],
              let partType = part["type"] as? String else {
            return [.rawEvent(sourceId: "opencode", json: raw)]
        }
        let delta = properties["delta"] as? String
        let fullText = part["text"] as? String

        switch partType {
        case "text":
            if let delta, !delta.isEmpty {
                answerAccumulator += delta
                answerSeq += 1
                return [.answerDelta(text: delta, sequence: answerSeq, isMarkdown: true)]
            }
            if let fullText {
                let suffix = Self.newSuffix(previous: answerAccumulator, current: fullText)
                if suffix.isEmpty { return [] }
                answerAccumulator = fullText
                answerSeq += 1
                return [.answerDelta(text: suffix, sequence: answerSeq, isMarkdown: true)]
            }
        case "reasoning":
            if let delta, !delta.isEmpty {
                reasoningAccumulator += delta
                reasoningSeq += 1
                return [.reasoningDelta(text: delta, sequence: reasoningSeq)]
            }
            if let fullText {
                let suffix = Self.newSuffix(previous: reasoningAccumulator, current: fullText)
                if suffix.isEmpty { return [] }
                reasoningAccumulator = fullText
                reasoningSeq += 1
                return [.reasoningDelta(text: suffix, sequence: reasoningSeq)]
            }
        case "tool":
            // Tool work is the deliverable for execute/review turns (a model can write a
            // file or run a check and never emit a closing assistant message). Record the
            // distinct call so an empty-text turn that *did* work isn't misread as a failure.
            let callID = (part["callID"] as? String) ?? (part["id"] as? String)
            if let callID { toolCallIDs.insert(callID) }
            let toolName = (part["tool"] as? String) ?? "tool"
            let status = (part["state"] as? [String: Any])?["status"] as? String
            return [.toolActivity(label: toolName, kind: status ?? "opencode")]
        default:
            break
        }
        return [.rawEvent(sourceId: "opencode", json: raw)]
    }

    /// Pull a short human reason out of a `session.error` event's `error` payload.
    /// The error is a union (`ProviderAuthError`, `UnknownError`, `MessageAbortedError`, …);
    /// prefer `data.message`, then `name`, else a compact JSON snippet.
    static func errorReason(_ properties: [String: Any]) -> String? {
        guard let error = properties["error"] as? [String: Any] else { return nil }
        if let data = error["data"] as? [String: Any], let message = data["message"] as? String, !message.isEmpty {
            return message
        }
        if let name = error["name"] as? String, !name.isEmpty { return name }
        if let json = try? JSONSerialization.data(withJSONObject: error),
           let s = String(data: json, encoding: .utf8) { return String(s.prefix(200)) }
        return nil
    }

    /// Returns the suffix of `current` beyond `previous` (handles cumulative updates).
    static func newSuffix(previous: String, current: String) -> String {
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        return current
    }
}
