import Foundation

/// Owner-facing agent labels for thread transcript rows (chat, mutating run, relay).
/// Plain threads: `Agent · Opus 5` + driver glyph. Relay threads: two-line
/// `Agent` + `Opus 5 · Claude · PM`.
public enum ThreadAgentPresentation {
    public enum RelaySeat: String, Sendable {
        case pm = "PM"
        case dev = "Dev"
    }

    public enum Layout: Sendable, Equatable {
        case plain
        case relay
    }

    public struct Label: Sendable, Equatable {
        public var layout: Layout
        public var driverId: String?
        /// Plain: full single-line header (`Agent · Opus 5`). Relay: primary line (`Agent`).
        public var primary: String
        /// Relay only: model · driver · seat (`Opus 5 · Claude · PM`).
        public var secondary: String?

        public init(layout: Layout, driverId: String?, primary: String, secondary: String? = nil) {
            self.layout = layout
            self.driverId = driverId
            self.primary = primary
            self.secondary = secondary
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
        var driverLabel: String?
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
        let driverLabel = resolvedDriver.map { ModelDisplayName.driverLabel(driverId: $0) }
        return Identity(name: name, driverLabel: driverLabel, driverId: resolvedDriver)
    }

    private static func plainLabel(identity: Identity) -> Label {
        Label(
            layout: .plain,
            driverId: identity.driverId,
            primary: "Agent · \(identity.name)"
        )
    }

    private static func relayLabel(identity: Identity, seat: RelaySeat) -> Label {
        var parts = [identity.name]
        if let driverLabel = identity.driverLabel { parts.append(driverLabel) }
        parts.append(seat.rawValue)
        return Label(
            layout: .relay,
            driverId: identity.driverId,
            primary: "Agent",
            secondary: parts.joined(separator: " · ")
        )
    }
}
