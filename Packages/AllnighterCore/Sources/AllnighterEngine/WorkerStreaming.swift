import Foundation
import AllnighterCore

/// A worker-level streaming event (03_Mac_Streaming §V1 Architecture). Only
/// `answerDelta` ever mutates visible chat text; `rawEvent`/`toolActivity` are
/// audit/optional and never the answer. Exactly one terminal event (`completed`
/// or `failed`) ends the stream.
public enum WorkerStreamEvent: Sendable, Equatable {
    case started(workerId: String, modelId: String, sourceId: String)
    /// A chunk of visible answer text. `sequence` is monotonic per run; `isMarkdown`
    /// hints whether the text should eventually render as Markdown.
    case answerDelta(text: String, sequence: Int, isMarkdown: Bool)
    /// One raw parsed event line, for debug/audit only — NEVER default UI text.
    case rawEvent(sourceId: String, json: String)
    /// Optional tool/activity hint a parser can map safely (e.g. "Editing file").
    case toolActivity(label: String, kind: String)
    case completed(WorkerRunOutcome)
    case failed(WorkerRunOutcome)
}

/// Per-invocation parser that turns a driver's raw byte stream into worker stream
/// events. State is PER PROCESS — never shared across runs. A class so its buffers
/// can mutate as the single stream-consuming task feeds it sequentially.
///
/// Implementation note (vs. the spec's `finish -> WorkerRunOutcome`): terminal
/// normalization (exit code → status, empty/capacity checks, ANSI strip) is owned
/// once by `WorkerRunner.finalize` and shared with the non-streaming path, so a
/// parser only owns answer framing + reconciliation. `finalAnswer` returns the
/// reconciled visible text (or nil to fall back to the manifest capture); the
/// runner builds the final `WorkerRunOutcome` from it.
public protocol WorkerStreamParser: AnyObject, Sendable {
    /// Parse a raw stdout byte chunk (NOT necessarily a full char/JSON line) into
    /// zero or more events. The parser owns UTF-8 + JSONL framing.
    func receiveStdout(_ data: Data) -> [WorkerStreamEvent]
    /// Parse a raw stderr chunk. Default chat answer text never comes from stderr.
    func receiveStderr(_ data: Data) -> [WorkerStreamEvent]
    /// Reconcile the final visible answer at settlement (the delta accumulator vs.
    /// the terminal result / output-file capture). Returns nil to defer to the
    /// manifest's normal final-output source.
    func finalAnswer(result: CommandResult, outputFileText: String?) -> String?
}

public extension WorkerStreamParser {
    func receiveStderr(_ data: Data) -> [WorkerStreamEvent] { [] }
}

/// Splits a byte stream into complete UTF-8 lines (JSONL), holding any trailing
/// partial line until more bytes arrive. Per-run state; not shared.
final class LineAssembler: @unchecked Sendable {
    private var buffer = Data()

    /// Append bytes and return any COMPLETE lines (newline-terminated), decoded as
    /// UTF-8. A trailing partial line stays buffered for the next chunk.
    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer[buffer.startIndex..<idx]
            if !lineData.isEmpty {
                lines.append(String(decoding: lineData, as: UTF8.self))
            }
            buffer.removeSubrange(buffer.startIndex...idx)
        }
        return lines
    }

    /// Any remaining buffered bytes as a final line (e.g. a last line with no
    /// trailing newline at process exit).
    func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return line.isEmpty ? nil : line
    }
}
