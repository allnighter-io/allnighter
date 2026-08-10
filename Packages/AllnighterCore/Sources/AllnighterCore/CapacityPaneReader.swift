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
        // Never inherit the parent CWD — Dock app / Xcode hosts often sit under
        // ~/Documents; a child CLI that stats cwd trips TCC as "Allnighter".
        if let scratch = CapacityProbe.neutralWorkingDirectory() {
            process.currentDirectoryURL = URL(fileURLWithPath: scratch, isDirectory: true)
        }
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

    // MARK: - Shadow mode (Handover_Capacity_2026-08-08.md §5, approved)
    //
    // Run this reader ALONGSIDE a deterministic parse that already succeeded,
    // and record whether they agree — never let the model's answer change
    // what ships. Founder's standing bet: *"It will show it is not needed.
    // Insurance will break first."* This exists to make that checkable rather
    // than argued, and to make the failure named in §6 visible: every failure
    // path in `read` above returns nil by design, so a typo'd argv and a
    // logged-out vendor look identical from the outside. A shadow read that
    // goes silent while the deterministic parser just succeeded is the one
    // signal that tells those two apart — which is why `modelSilent` below is
    // itself a logged disagreement, not a discarded nil.

    /// One recorded disagreement between the deterministic parser and the
    /// shadow model read, for the SAME capture. Never a counter — a source,
    /// a timestamp, both answers, and enough of the pane to adjudicate later.
    public struct Disagreement: Equatable, Sendable, Codable {
        /// What kind of disagreement this is, so a reviewer does not have to
        /// re-derive it from the raw fields every time.
        public enum Kind: String, Equatable, Sendable, Codable {
            /// Both produced a confident number; they differ beyond tolerance.
            case valueMismatch
            /// The model answered but declined to be confident, or gave no
            /// number, while the parser read a real value from the same text.
            case modelUnconfident
            /// The shadow spawn produced nothing at all — no binary, timeout,
            /// non-zero exit, or unparseable output — while the parser
            /// succeeded on the same capture. The case §6 warns about: this is
            /// indistinguishable from "vendor unavailable" without shadow mode.
            case modelSilent
        }

        public var source: String
        public var observedAt: Date
        public var kind: Kind
        public var parserRemainingPercent: Double
        public var parserResetAt: Date?
        public var modelRemainingPercent: Double?
        /// Nil only for `modelSilent`, where there was no reading to ask.
        public var modelConfident: Bool?
        public var modelReason: String?
        /// Truncated, bounded-length. This is the captured USAGE PANE only
        /// (never a full session transcript), but still capped and never
        /// includes account ids or credentials — the pane text itself never
        /// carries them (Capacity_Native_Channels.md never reads a credential).
        public var captureExcerpt: String

        public init(
            source: String,
            observedAt: Date,
            kind: Kind,
            parserRemainingPercent: Double,
            parserResetAt: Date?,
            modelRemainingPercent: Double?,
            modelConfident: Bool?,
            modelReason: String?,
            captureExcerpt: String
        ) {
            self.source = source
            self.observedAt = observedAt
            self.kind = kind
            self.parserRemainingPercent = parserRemainingPercent
            self.parserResetAt = parserResetAt
            self.modelRemainingPercent = modelRemainingPercent
            self.modelConfident = modelConfident
            self.modelReason = modelReason
            self.captureExcerpt = captureExcerpt
        }
    }

    /// Longest capture excerpt kept in a logged disagreement.
    static let captureExcerptLimit = 4000

    /// Pure comparison — no spawn, no IO. `reading` is nil for a shadow read
    /// that produced nothing (missing binary, timeout, non-zero exit, or
    /// unparseable output); every other nil path already collapsed to this by
    /// the time it reaches here.
    ///
    /// Returns nil on agreement — an agreement is not logged, by design (the
    /// log exists to be reviewable, and a file of "agreed" lines is noise).
    public static func compareToParser(
        parsed: [CapacityWindow],
        reading: Reading?,
        source: String,
        capture: String,
        now: Date,
        tolerancePercent: Double = 1.0
    ) -> Disagreement? {
        // The parser's own "most constrained" pool, same rule as the prompt
        // asks the model for — the two numbers are only comparable if they
        // answer the same question.
        guard let parserRemaining = parsed.compactMap(\.remainingPercent).min() else { return nil }
        let parserWindow = parsed.first { $0.remainingPercent == parserRemaining }
        let excerpt = String(capture.prefix(captureExcerptLimit))

        guard let reading else {
            return Disagreement(
                source: source, observedAt: now, kind: .modelSilent,
                parserRemainingPercent: parserRemaining, parserResetAt: parserWindow?.resetAt,
                modelRemainingPercent: nil, modelConfident: nil, modelReason: nil,
                captureExcerpt: excerpt
            )
        }
        guard reading.confident, let modelRemaining = reading.mostConstrainedRemaining else {
            return Disagreement(
                source: source, observedAt: now, kind: .modelUnconfident,
                parserRemainingPercent: parserRemaining, parserResetAt: parserWindow?.resetAt,
                modelRemainingPercent: reading.mostConstrainedRemaining, modelConfident: reading.confident,
                modelReason: reading.reason, captureExcerpt: excerpt
            )
        }
        guard abs(modelRemaining - parserRemaining) <= tolerancePercent else {
            return Disagreement(
                source: source, observedAt: now, kind: .valueMismatch,
                parserRemainingPercent: parserRemaining, parserResetAt: parserWindow?.resetAt,
                modelRemainingPercent: modelRemaining, modelConfident: true,
                modelReason: reading.reason, captureExcerpt: excerpt
            )
        }
        return nil
    }

    /// Spawn + extract only — no comparison, no logging. Same shape as
    /// `read`, minus building `CapacityWindow`s, because shadow mode wants
    /// the raw `Reading` (including an unconfident one) to compare and log,
    /// not just a pass/fail window.
    static func shadowRead(
        source: String,
        capture: String,
        executable: String,
        timeout: TimeInterval
    ) -> Reading? {
        guard let argv = readerArgv(for: source, prompt: prompt + capture) else { return nil }
        guard let output = runHeadless(executable: executable, argv: argv, timeout: timeout) else { return nil }
        return extractReading(from: output)
    }

    /// Run the shadow read against a capture the deterministic parser already
    /// read successfully, and return a `Disagreement` when the two do not
    /// agree — nil on agreement, and nil for a source with no declared reader
    /// argv (fail closed rather than inventing a "not wired" signal).
    public static func runShadowComparison(
        source: String,
        capture: String,
        executable: String,
        parsed: [CapacityWindow],
        timeout: TimeInterval = 90,
        now: Date = Date()
    ) -> Disagreement? {
        guard readerArgv(for: source, prompt: "") != nil else { return nil }
        let reading = shadowRead(source: source, capture: capture, executable: executable, timeout: timeout)
        return compareToParser(parsed: parsed, reading: reading, source: source, capture: capture, now: now)
    }

    // MARK: - Shadow log

    /// Where a caller writes a shadow disagreement, injectable so production
    /// code and tests never share a sink.
    public protocol ShadowDisagreementSink: Sendable {
        func append(_ disagreement: Disagreement)
    }

    /// One append-only JSONL file, one line per disagreement.
    public struct FileShadowDisagreementSink: ShadowDisagreementSink {
        public let url: URL

        public init(url: URL = CapacityPaneReader.defaultShadowLogURL) {
            self.url = url
        }

        public func append(_ disagreement: Disagreement) {
            // Backstop, deliberately redundant with sink injection — the same
            // shape as `CapacityAccuracyLedger.FileSink`, which exists
            // because a forgotten injection once wrote 45 fake rows into the
            // founder's real evidence file. Do not delete this as redundant.
            guard !CapacityPaneReader.isRunningUnderTestRunner else { return }
            CapacityPaneReader.write(disagreement, to: url)
        }
    }

    public static var defaultShadowLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Allnighter/Capacity/shadow/disagreements.jsonl",
                isDirectory: false
            )
    }

    static var isRunningUnderTestRunner: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if env["SWIFT_TESTING_ENABLED"] != nil { return true }
        if Bundle.main.bundlePath.contains(".xctest") { return true }
        if ProcessInfo.processInfo.arguments.first?.contains(".xctest") == true { return true }
        return false
    }

    /// Append one JSONL line. Best-effort: a write failure never propagates —
    /// shadow logging must not be able to break capacity.
    static func write(_ disagreement: Disagreement, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(disagreement)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url)
            }
        } catch {
            // Best-effort log — never blocks or fails the capacity strip.
        }
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
