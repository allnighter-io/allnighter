import Foundation

/// Postcard to a person. Quoted text, CLI version, and OS only — never repo,
/// prompts, run journals, or files. Opt-in: the human typed the message.
public struct FeedbackPayload: Codable, Equatable, Sendable {
    public var message: String
    public var binaryVersion: String
    public var os: String

    public init(message: String, binaryVersion: String, os: String) {
        self.message = message
        self.binaryVersion = binaryVersion
        self.os = os
    }

    public static func make(
        message: String,
        binaryVersion: String = AllnighterVersionIdentity.binaryVersion,
        os: String = FeedbackOS.current
    ) -> FeedbackPayload {
        FeedbackPayload(message: message, binaryVersion: binaryVersion, os: os)
    }
}

public struct FeedbackJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sent: Bool
    public var dryRun: Bool
    public var payload: FeedbackPayload
    public var tellHuman: String

    public init(
        schemaVersion: Int = 1,
        sent: Bool,
        dryRun: Bool,
        payload: FeedbackPayload,
        tellHuman: String
    ) {
        self.schemaVersion = schemaVersion
        self.sent = sent
        self.dryRun = dryRun
        self.payload = payload
        self.tellHuman = tellHuman
    }

    public static func preview(_ payload: FeedbackPayload, dryRun: Bool, sent: Bool) -> FeedbackJSON {
        FeedbackJSON(
            sent: sent,
            dryRun: dryRun,
            payload: payload,
            tellHuman: dryRun ? SupportHatch.feedbackDryRunTellHuman : SupportHatch.feedbackSentTellHuman
        )
    }
}

public enum FeedbackOS {
    public static var current: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

public enum FeedbackError: Error, Equatable, Sendable {
    case empty
    case tooLong(limit: Int)
    case rateLimited(limit: Int)
    case unavailable(detail: String)
    case rejected(detail: String)
}

public protocol FeedbackTransporting: Sendable {
    func post(_ payload: FeedbackPayload) async throws -> (status: Int, body: Data)
}

public struct URLSessionFeedbackTransport: FeedbackTransporting {
    public static let defaultBaseURL = URL(string: "https://feedback.allnighter.io/")!
    public static let baseURLEnvKey = "ALLNIGHTER_FEEDBACK_URL"

    let endpoint: URL
    let session: URLSession

    public init(endpoint: URL? = nil, session: URLSession? = nil) {
        if let endpoint {
            self.endpoint = endpoint
        } else if let raw = ProcessInfo.processInfo.environment[Self.baseURLEnvKey],
                  let url = URL(string: raw), !raw.isEmpty {
            self.endpoint = url
        } else {
            self.endpoint = Self.defaultBaseURL
        }
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: config)
        }
    }

    public func post(_ payload: FeedbackPayload) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CoreJSON.encode(payload)
        let (body, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, body)
    }
}

public struct FeedbackRateStore: Sendable {
    public static let dailyLimit = 5
    private let directory: URL
    private let clock: @Sendable () -> Date

    public init(
        directory: URL = AllnighterSupportRoot.support,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.clock = clock
    }

    public func remaining() -> Int {
        max(0, Self.dailyLimit - stamps(on: clock()).count)
    }

    public func consume() -> Bool {
        let now = clock()
        var today = stamps(on: now)
        guard today.count < Self.dailyLimit else { return false }
        today.append(now.timeIntervalSince1970)
        save(today)
        return true
    }

    private func stamps(on now: Date) -> [TimeInterval] {
        let day = Self.dayKey(now)
        let all = load()
        return all.filter { Self.dayKey(Date(timeIntervalSince1970: $0)) == day }
    }

    private func load() -> [TimeInterval] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stamps = obj["sentAt"] as? [TimeInterval]
        else { return [] }
        return stamps
    }

    private func save(_ stamps: [TimeInterval]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try? JSONSerialization.data(
            withJSONObject: ["sentAt": stamps],
            options: [.sortedKeys]
        )
        try? data?.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private var fileURL: URL {
        directory.appendingPathComponent("feedback-rate.json")
    }

    static func dayKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public struct FeedbackService: Sendable {
    public static let maxMessageLength = 2_000

    let transport: any FeedbackTransporting
    let rate: FeedbackRateStore

    public static let standard = FeedbackService()

    public init(
        transport: any FeedbackTransporting = URLSessionFeedbackTransport(),
        rate: FeedbackRateStore = FeedbackRateStore()
    ) {
        self.transport = transport
        self.rate = rate
    }

    public func prepare(message: String) -> Result<FeedbackPayload, FeedbackError> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.count > Self.maxMessageLength {
            return .failure(.tooLong(limit: Self.maxMessageLength))
        }
        return .success(FeedbackPayload.make(message: trimmed))
    }

    public func preview(message: String) -> Result<FeedbackJSON, FeedbackError> {
        switch prepare(message: message) {
        case .failure(let error): return .failure(error)
        case .success(let payload): return .success(.preview(payload, dryRun: true, sent: false))
        }
    }

    public func send(message: String) async -> Result<FeedbackJSON, FeedbackError> {
        switch prepare(message: message) {
        case .failure(let error): return .failure(error)
        case .success(let payload):
            guard rate.remaining() > 0 else {
                return .failure(.rateLimited(limit: FeedbackRateStore.dailyLimit))
            }
            do {
                let (status, body) = try await transport.post(payload)
                if (200..<300).contains(status) {
                    guard rate.consume() else {
                        return .failure(.rateLimited(limit: FeedbackRateStore.dailyLimit))
                    }
                    return .success(.preview(payload, dryRun: false, sent: true))
                }
                let detail = String(decoding: body, as: UTF8.self)
                if status == 503 || status == 0 {
                    return .failure(.unavailable(detail: detail))
                }
                return .failure(.rejected(detail: detail.isEmpty ? "HTTP \(status)" : detail))
            } catch {
                return .failure(.unavailable(detail: error.localizedDescription))
            }
        }
    }
}
