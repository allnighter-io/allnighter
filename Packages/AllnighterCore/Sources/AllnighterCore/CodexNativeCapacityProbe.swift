import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Parser + acquisition for codex's **native** app-server JSON-RPC channel —
/// the primary acquisition path for `codex` (`Capacity_Native_Channels.md`
/// §2), replacing the `/status` TUI screen scrape (`CodexCapacityProbe`) as
/// the seat's fallback.
///
/// Channel: `codex app-server --listen stdio://`, newline-delimited JSON-RPC
/// on stdin/stdout — `initialize` then `account/rateLimits/read`. Measured on
/// the dogfood host: sub-second reply, zero credentials (codex owns its own
/// auth and refresh in-process), no PTY, no rendered screen. An epoch integer
/// for `resetsAt` has no timezone to misinterpret — that is the whole reason
/// this channel deletes the bug class the TUI parser's local/UTC ambiguity
/// belongs to, rather than merely working around it.
///
/// Attribution: this parser answers only for `sourceId == "codex"` — it is
/// never applied to another vendor's payload and never influences one.
///
/// Fail closed, always. Never throws. A JSON-RPC error response, a spawn
/// failure, a timeout, malformed/empty output, a response we never matched by
/// `id`, or an unrecognized shape produces no windows — never an inferred
/// number. `secondary: null` (no short window on this plan) is not fabricated
/// into a fiveHour window; the caller's `shortWindowNone` stays true, which is
/// the honest outcome.
public enum CodexNativeCapacityProbe {

    /// argv for `codex app-server` in stdio JSON-RPC mode.
    public static let argv: [String] = ["app-server", "--listen", "stdio://"]

    /// Our own external wall-clock budget for the child process. Measured wall
    /// time on the dogfood host is well under 1s — this is headroom, kept well
    /// under the acquisition ladder's per-source budget
    /// (`CapacityProbe.timeout(for: "codex")` = 20s) so a slow native attempt
    /// still leaves time for the TUI fallback within the same probe call.
    public static let processTimeout: TimeInterval = 10

    static let initializeRequestId = 1
    static let rateLimitsRequestId = 2

    // MARK: - Public entry

    /// Run the channel end to end: spawn `codex app-server`, write both
    /// requests, read until the `account/rateLimits/read` response (id 2)
    /// arrives or the budget expires, parse it, and ALWAYS kill the child —
    /// app-server is a persistent server and will not exit on its own once it
    /// has answered. Orphaning it here would recreate the 103-process leak
    /// that starved this machine's probes on 2026-08-08.
    ///
    /// Returns `nil` on any failure so the caller falls through to the TUI
    /// probe unchanged.
    public static func fetch(
        executable: String,
        now: Date,
        timeout: TimeInterval = processTimeout
    ) -> [CapacityWindow]? {
        guard let line = runJSONRPC(
            executable: executable,
            requestBody: requestLines(),
            timeout: timeout,
            matchId: rateLimitsRequestId
        ) else { return nil }
        let windows = capacityWindows(fromResponseLine: line, observedAt: now)
        return windows.isEmpty ? nil : windows
    }

    /// The two newline-delimited JSON-RPC requests written to stdin up front.
    /// `initialize` first (codex expects the handshake), then the rate-limits
    /// read. Encoded with `JSONSerialization` rather than a hand-built string
    /// so key ordering/escaping is never our problem.
    static func requestLines() -> String {
        let initialize: [String: Any] = [
            "jsonrpc": "2.0",
            "id": initializeRequestId,
            "method": "initialize",
            "params": ["clientInfo": ["name": "alln", "version": "0"]],
        ]
        let rateLimits: [String: Any] = [
            "jsonrpc": "2.0",
            "id": rateLimitsRequestId,
            "method": "account/rateLimits/read",
            "params": [String: Any](),
        ]
        let lines: [String] = [initialize, rateLimits].compactMap { obj in
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return lines.map { $0 + "\n" }.joined()
    }

    // MARK: - Response parse (fail closed)

    /// Parse one matched JSON-RPC response line into normalized windows.
    /// Never throws. Returns `[]` on: malformed JSON, a JSON-RPC `error`
    /// response, missing `result.rateLimits`, or a `primary`/`secondary` slot
    /// with an unrecognized `windowDurationMins` or missing fields.
    public static func capacityWindows(fromResponseLine line: String, observedAt: Date) -> [CapacityWindow] {
        guard let data = line.data(using: .utf8) else { return [] }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            root = obj
        } catch {
            return []
        }

        // A JSON-RPC error response is a declared failure — never partially
        // trusted, never inferred around.
        if root["error"] != nil { return [] }

        guard let result = root["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else { return [] }

        let planType = rateLimits["planType"] as? String

        var windows: [CapacityWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any],
           let window = parseSlot(primary, observedAt: observedAt, planType: planType) {
            windows.append(window)
        }
        // secondary is legitimately null on a plan with no short window (this
        // host: weekly-only). Absence here is never fabricated into a
        // fiveHour window — CapacityStripRenderer derives `shortWindowNone`
        // from exactly this absence.
        if let secondary = rateLimits["secondary"] as? [String: Any],
           let window = parseSlot(secondary, observedAt: observedAt, planType: planType) {
            windows.append(window)
        }
        return windows
    }

    private static func parseSlot(
        _ slot: [String: Any],
        observedAt: Date,
        planType: String?
    ) -> CapacityWindow? {
        // usedPercent is codex's own used-polarity number
        // (`CodexCapacityLog.swift`), 0…100+, never inverted or defaulted.
        guard let usedPercent = doubleValue(slot["usedPercent"]) else { return nil }
        guard let minutes = intValue(slot["windowDurationMins"]) else { return nil }
        guard let scope = scope(forWindowMinutes: minutes) else { return nil }
        guard let resetsAt = unixDate(slot["resetsAt"]) else { return nil }

        return CapacityWindow(
            used: usedPercent,
            source: "codex",
            scope: scope,
            resetAt: resetsAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .headlessJSON,
            planTier: planType
        )
    }

    /// Only 10080 (weekly) and 300 (fiveHour) — the same scopes
    /// `CodexCapacityLog` recognizes from the on-disk rollout log. An
    /// unrecognized duration is dropped, not guessed at.
    private static func scope(forWindowMinutes minutes: Int) -> CapacityWindowScope? {
        switch minutes {
        case 10_080: return .weekly
        case 300: return .fiveHour
        default: return nil
        }
    }

    // The `NSNumber`/`CFBoolean` branch is checked FIRST in every helper
    // below, before falling back to `any as? Double`/`any as? Int` — those
    // direct casts also succeed for a CFBoolean-backed NSNumber (JSON
    // `true`/`false` bridges to one), coercing it into `1.0`/`1` before the
    // CFBoolean guard ever runs. Do NOT "fix" this with a blanket `any is
    // Bool` pre-check instead: Swift's NSNumber/Bool bridging has its own
    // trap the other way — `(0 as NSNumber) is Bool` and `(1 as NSNumber) is
    // Bool` are BOTH `true` on Darwin, so that shortcut would silently
    // refuse a legitimate 0%/1% `usedPercent` too. `CFGetTypeID` against
    // `CFBooleanGetTypeID()` is the only discriminator that gets both
    // directions right.

    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        }
        if let i = any as? Int { return i }
        return nil
    }

    private static func unixDate(_ any: Any?) -> Date? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        if let i = any as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let d = any as? Double { return Date(timeIntervalSince1970: d) }
        return nil
    }

    // MARK: - Process I/O

    /// Spawn `executable` with `argv`, write `requestBody` to stdin, and poll
    /// stdout for a JSON-RPC line whose `"id"` equals `matchId` — tolerating
    /// any interleaved notification (codex emits an unsolicited
    /// `remoteControl/status/changed` between the two responses) or the
    /// `initialize` response (id 1) arriving first.
    ///
    /// A plain pipe, not a PTY — this is a JSON-RPC server speaking on
    /// stdio, not a screen to render. Every return path below kills the
    /// child: app-server does not exit on its own once it has answered, so
    /// leaving it running would leak exactly the orphan class
    /// `Capacity_Native_Channels.md` blames for a day of "flaky" capacity.
    static func runJSONRPC(
        executable: String,
        requestBody: String,
        timeout: TimeInterval,
        matchId: Int
    ) -> String? {
        #if canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = argv
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        process.environment = environment

        do { try process.run() } catch { return nil }

        func killChild() {
            if process.isRunning {
                kill(-process.processIdentifier, SIGKILL)
            }
            process.terminate()
            // Close our end now that the child is going away — otherwise the
            // write handle leaks for the life of this (long-running) alln
            // process. Never close it BEFORE this: measured live against
            // `codex app-server`, closing stdin — even well after both
            // requests were written — makes it exit without ever answering
            // `account/rateLimits/read`. It reads EOF as a shutdown signal and
            // abandons in-flight work rather than finishing it.
            try? stdinPipe.fileHandleForWriting.close()
        }

        guard let requestData = requestBody.data(using: .utf8) else {
            killChild()
            return nil
        }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: requestData)
        } catch {
            killChild()
            return nil
        }
        // Deliberately NOT closing stdin here — see the comment in
        // `killChild()`. The pipe stays open for the life of this call; the
        // child is a short-lived probe we kill ourselves either way.

        var buffer = Data()
        let lock = NSLock()
        let drain = Thread {
            while true {
                let chunk = stdoutPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                lock.lock(); buffer.append(chunk); lock.unlock()
            }
        }
        drain.start()

        func scanForMatch() -> String? {
            lock.lock(); let snapshot = buffer; lock.unlock()
            guard let text = String(data: snapshot, encoding: .utf8) else { return nil }
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let matched = matchingLine(String(rawLine), id: matchId) { return matched }
            }
            return nil
        }

        var matchedLine: String?
        let deadline = Date().addingTimeInterval(timeout)
        while matchedLine == nil, Date() < deadline, process.isRunning {
            matchedLine = scanForMatch()
            if matchedLine == nil {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        // One last look at whatever arrived right before the loop exited —
        // covers the deadline-hit and process-died races alike.
        if matchedLine == nil {
            matchedLine = scanForMatch()
        }

        killChild()
        return matchedLine
        #else
        return nil
        #endif
    }

    /// `line` decodes as a JSON object whose `"id"` equals `id`. Returns the
    /// trimmed line itself (not the parsed object — the caller's own parser
    /// owns interpretation), or `nil` for anything else: a notification with
    /// no `id`, a response for a different request, or unparseable text.
    static func matchingLine(_ line: String, id: Int) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let lineId = intValue(obj["id"]) else { return nil }
        return lineId == id ? trimmed : nil
    }
}
