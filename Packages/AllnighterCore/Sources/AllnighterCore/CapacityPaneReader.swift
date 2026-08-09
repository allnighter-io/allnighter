import Foundation

/// Read a captured usage pane with the vendor's own cheapest model, when the
/// deterministic parser could not read it.
///
/// ## Why
///
/// The deterministic path needs four things per source — a readiness predicate,
/// a marker list, a usage-pane detector, and a parser. On 2026-08-08 **all four
/// broke at least once**: a misspelled guard, a generic `"tip:"` matching
/// codex's own boot chrome, `"settings"` matching cursor's composer, and every
/// empty parse blaming the parser. None of those were reading failures; they
/// were matching failures.
///
/// Measured against real captures (packet §4b), one generic prompt read **six
/// different vendors' screen formats** at 10/10, and returned `null` with
/// `confident: false` on every capture that had no usage data — splash
/// animations, boot chrome, a bare composer. Zero invented numbers.
///
/// ## Why the vendor's own model
///
/// Founder's design, and the elegant part is what happens when it fails: asking
/// vendor X's cheapest model to read vendor X's screen means a failed call *is*
/// the availability answer. There is no error case to disambiguate — either we
/// get the numbers, or that seat is not usable right now, which is what the
/// capacity question was asking in the first place.
///
/// It also needs no credentials, no API key and no local hardware: it is the
/// user's existing subscription, the same one the pane belongs to.
///
/// ## Scope
///
/// Fallback only. The deterministic parse runs first and costs nothing; this
/// runs when that returns empty, which is rare. `unknown` is a valid answer and
/// is believed — a loud "I could not tell" is cheap, a confident wrong number is
/// not.
public enum CapacityPaneReader {

    /// What the model is asked to return. Deliberately small and total: every
    /// field may be null, and `confident: false` is a first-class answer rather
    /// than a failure.
    public struct Reading: Equatable, Sendable, Codable {
        public struct Pool: Equatable, Sendable, Codable {
            public var label: String?
            public var remainingPercent: Double?
        }
        public var pools: [Pool]
        public var mostConstrainedRemaining: Double?
        public var resetAt: String?
        public var planTier: String?
        public var confident: Bool
        public var reason: String?
    }

    /// One prompt for every vendor. That is the point — the deterministic path
    /// needs four per-source artifacts and this needs none.
    ///
    /// The pool rule is load-bearing. Cursor's pane lists Included / Auto / API
    /// at 57 / 58 / 52 percent remaining; without saying which one wins, a
    /// correct reading of the wrong row looks like an error. It is not — it is
    /// an underspecified question, and that was the only miss in the §4b run.
    public static let prompt = """
    You are reading raw terminal output captured from a coding CLI's usage/status screen.

    Reply with ONLY this JSON, no prose and no code fence:
    {"pools":[{"label":"<name or null>","remainingPercent":<number>}],\
    "mostConstrainedRemaining":<number or null>,"resetAt":"<ISO8601 or null>",\
    "planTier":"<string or null>","confident":<true|false>,"reason":"<max 12 words>"}

    RULES:
    - A screen may list SEVERAL quota pools. Report every one you can see.
    - Screens often show USED percent. Convert: remaining = 100 - used.
    - mostConstrainedRemaining = the LOWEST remaining across the pools.
    - Some captures are only a splash animation, a boot screen, or a chat prompt \
    with NO usage information. If so, return pools: [], null values, and \
    confident: false. Do NOT guess, infer, or estimate.
    - If the screen is half-painted or ambiguous, say confident: false rather \
    than reporting a number you are unsure of.
    - Ignore context-window percentages (e.g. "100% context left") and dollar \
    amounts — neither is account quota.

    CAPTURE:

    """

    /// Full headless argv for a source's own cheapest model, prompt included.
    ///
    /// Returns the WHOLE command line rather than a flag list, because prompt
    /// placement is not uniform — `agy --print "<prompt>" --output-format json`
    /// wants it immediately after the flag, while cursor and grok take it last.
    /// Encoding that per vendor here keeps it in one visible table instead of
    /// scattered across a caller.
    ///
    /// Cheapest seat, because this is telemetry: spending a premium model to
    /// measure how much of that model is left would be self-defeating.
    ///
    /// nil for a source with no known headless print mode — which fails closed,
    /// producing no reading rather than a guess.
    public static func readerArgv(for source: String, prompt: String) -> [String]? {
        switch source {
        case "cursor_agent":
            return ["-p", prompt, "--output-format", "json", "--model", "composer-2.5"]
        case "agy":
            return ["--print", prompt, "--output-format", "json", "--print-timeout", "90s"]
        case "claude_code":
            return ["-p", prompt, "--output-format", "json", "--model", "haiku"]
        case "grok":
            return ["-p", prompt, "--output-format", "json"]
        case "kimi":
            return ["-p", prompt]
        case "codex":
            return ["exec", "--json", prompt]
        default:
            return nil
        }
    }

    /// Which seat each source reads with, for disclosure and for tests. The
    /// model id is part of the product surface — a user turning this off should
    /// be able to see what it was going to spend.
    public static func readerSeat(for source: String) -> String? {
        switch source {
        case "cursor_agent": return "composer-2.5"
        case "claude_code": return "haiku"
        case "agy", "grok", "kimi", "codex": return "default (cheapest configured)"
        default: return nil
        }
    }

    /// Extract the model's JSON object from whatever wrapper the CLI printed.
    ///
    /// Every vendor wraps differently — some emit an envelope with the answer as
    /// a string field, some print bare text, some fence it. Rather than a parser
    /// per vendor (the exact thing this replaces), take the LAST balanced
    /// top-level JSON object containing our marker key. Last, not first, because
    /// an envelope's own `{...}` header often precedes the answer.
    public static func extractReading(from output: String) -> Reading? {
        // Shape 1: the answer is printed bare, possibly among other lines.
        for candidate in balancedObjects(in: output).reversed() where candidate.contains("\"confident\"") {
            if let reading = decode(candidate) { return reading }
        }
        // Shape 2: the CLI wraps it, and the answer arrives as an ESCAPED STRING
        // inside the envelope (cursor-agent does this: `{"type":"result",
        // "result":"{\"pools\":..."}`). Brace scanning cannot see inside a
        // JSON string, so walk the parsed envelope for any string value that
        // decodes as a Reading. Two shapes, still one code path — the
        // alternative is an envelope parser per vendor, which is the thing this
        // whole approach exists to avoid.
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return readingInAnyStringValue(of: root)
    }

    private static func readingInAnyStringValue(of node: Any) -> Reading? {
        switch node {
        case let text as String:
            guard text.contains("\"confident\"") else { return nil }
            for candidate in balancedObjects(in: text).reversed() {
                if let reading = decode(candidate) { return reading }
            }
            return nil
        case let dict as [String: Any]:
            for value in dict.values {
                if let reading = readingInAnyStringValue(of: value) { return reading }
            }
            return nil
        case let list as [Any]:
            for value in list.reversed() {
                if let reading = readingInAnyStringValue(of: value) { return reading }
            }
            return nil
        default:
            return nil
        }
    }

    private static func decode(_ json: String) -> Reading? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Reading.self, from: data)
    }

    /// Every balanced `{...}` span, ignoring braces inside strings and escapes.
    static func balancedObjects(in text: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for index in text.indices {
            let ch = text[index]
            if escaped { escaped = false; continue }
            if ch == "\\" { if inString { escaped = true }; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let from = start {
                    out.append(String(text[from...index]))
                    start = nil
                } else if depth < 0 {
                    depth = 0
                    start = nil
                }
            }
        }
        return out
    }

    /// Windows for a reading, or nil when the model declined to answer.
    ///
    /// `confident: false` is believed rather than second-guessed, and so is a
    /// missing number. Producing a window from an unconfident reading would
    /// reintroduce exactly the invented-value problem this whole packet exists
    /// to remove.
    public static func windows(
        from reading: Reading,
        source: String,
        now: Date
    ) -> [CapacityWindow]? {
        guard reading.confident else { return nil }
        guard let remaining = reading.mostConstrainedRemaining,
              remaining >= 0, remaining <= 100
        else { return nil }
        return [
            CapacityWindow(
                used: 100.0 - remaining,
                source: source,
                scope: .weekly,
                resetAt: reading.resetAt.flatMap(parseISO8601),
                resetPrecision: reading.resetAt == nil ? .day : .exact,
                observedAt: now,
                sourceTier: .tuiProbe,
                planTier: reading.planTier
            ),
        ]
    }

    /// Spawn the source's own cheapest seat to read `capture`, and return
    /// windows if it answered confidently.
    ///
    /// A plain pipe, not a PTY: print mode is non-interactive by definition, and
    /// a PTY here would reintroduce the repaint behaviour this exists to escape.
    ///
    /// Every failure path returns nil — no binary, no print mode, non-zero exit,
    /// timeout, unparseable output, or an unconfident reading. That is the
    /// design, not defensiveness: when the vendor's own model cannot answer,
    /// that seat is not usable right now, which is the capacity question. There
    /// is no error state to disambiguate.
    public static func read(
        source: String,
        capture: String,
        executable: String,
        timeout: TimeInterval = 90,
        now: Date = Date()
    ) -> [CapacityWindow]? {
        guard let argv = readerArgv(for: source, prompt: prompt + capture) else { return nil }
        guard let output = runHeadless(executable: executable, argv: argv, timeout: timeout)
        else { return nil }
        guard let reading = extractReading(from: output) else { return nil }
        return windows(from: reading, source: source, now: now)
    }

    /// Non-interactive capture of a child's stdout. Kills the whole process
    /// group on timeout — a reader that leaks children would recreate the leak
    /// that loaded this machine badly enough to break the probes in the first
    /// place.
    static func runHeadless(executable: String, argv: [String], timeout: TimeInterval) -> String? {
        #if canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = argv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment.removeValue(forKey: "NO_COLOR")
        process.environment = environment
        do { try process.run() } catch { return nil }

        // Drain concurrently: a full pipe buffer would deadlock a child that is
        // still writing while we wait for exit.
        var data = Data()
        let lock = NSLock()
        let drain = Thread {
            let chunk = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); data.append(chunk); lock.unlock()
        }
        drain.start()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(-process.processIdentifier, SIGKILL)
            process.terminate()
            return nil
        }
        // Let the drain settle now that the writer is gone.
        let settle = Date().addingTimeInterval(2)
        while drain.isExecuting, Date() < settle {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.terminationStatus == 0 else { return nil }
        lock.lock(); let out = String(data: data, encoding: .utf8); lock.unlock()
        return out
        #else
        return nil
        #endif
    }

    static func parseISO8601(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Vendors print local time without a zone often enough to be worth one
        // more attempt; anything else is dropped rather than guessed.
        let loose = DateFormatter()
        loose.locale = Locale(identifier: "en_US_POSIX")
        loose.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return loose.date(from: text)
    }
}
