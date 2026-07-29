import Foundation

/// Owner-facing agent labels for thread transcript rows (chat, mutating run, relay).
/// Plain threads: `Agent · Opus 5`. Relay threads: `Dev · Grok Build` (seat · model).
/// The Mac UI appends time on the same row (` · 4:23 AM`).
public enum ThreadAgentPresentation {
    public enum RelaySeat: String, Sendable {
        case pm = "PM"
        case dev = "Dev"
    }

    public struct Label: Sendable, Equatable {
        public var driverId: String?
        /// Single-line header before time — `Agent · Opus 5` or `Dev · Grok Build`.
        public var primary: String

        public init(driverId: String?, primary: String) {
            self.driverId = driverId
            self.primary = primary
        }
    }

    public static func isRelayThread(threadId: String) -> Bool {
        threadId.hasPrefix("relay_")
    }

    /// PM/dev seat encoded in relay projector turn ids (`<relayId>_pm<round>`, `_dev<round>`).
    public static func relaySeat(threadId: String, turnId: String) -> RelaySeat? {
        guard isRelayThread(threadId: threadId) else { return nil }
        if turnId.range(of: "_pm\\d+$", options: .regularExpression) != nil { return .pm }
        if turnId.range(of: "_dev\\d+$", options: .regularExpression) != nil { return .dev }
        return nil
    }

    public static func make(
        threadId: String,
        turnId: String,
        modelId: String?,
        modelDisplayName: String?,
        driverId: String?
    ) -> Label {
        let identity = resolvedIdentity(modelId: modelId, modelDisplayName: modelDisplayName, driverId: driverId)
        if isRelayThread(threadId: threadId), let seat = relaySeat(threadId: threadId, turnId: turnId) {
            return relayLabel(identity: identity, seat: seat)
        }
        return plainLabel(identity: identity)
    }

    // MARK: - Identity

    private struct Identity: Sendable {
        var name: String
        var driverId: String?
    }

    private static func resolvedIdentity(
        modelId: String?,
        modelDisplayName: String?,
        driverId: String?
    ) -> Identity {
        let trimmedId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = modelDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if let trimmedName, !trimmedName.isEmpty {
            name = trimmedName
        } else if let trimmedId, !trimmedId.isEmpty {
            name = trimmedId
        } else {
            name = "unknown"
        }
        let trimmedDriver = driverId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDriver = (trimmedDriver?.isEmpty == false) ? trimmedDriver : nil
        return Identity(name: name, driverId: resolvedDriver)
    }

    private static func plainLabel(identity: Identity) -> Label {
        Label(driverId: identity.driverId, primary: "Agent · \(identity.name)")
    }

    private static func relayLabel(identity: Identity, seat: RelaySeat) -> Label {
        Label(driverId: identity.driverId, primary: "\(seat.rawValue) · \(identity.name)")
    }
}
