import Foundation

/// Enable-time law for discovered local Ollama tags (OCL-S03 / packet §0.2, §7.3, §7.7).
///
/// The agent body is chosen here, not at discovery. Explicit enable discloses
/// G1 / served-context facts and proceeds. Automatic Code offers stay gated.
/// Provenance is not a refuse-class.
public enum OllamaLocalSeatEnablePolicy {
    public static let allowedBodies: Set<String> = ["claude_code", "opencode"]
    /// Packet §7.3 gate 4 — automatic Code offer only. Explicit enable is
    /// warn-and-allow below this floor.
    public static let automaticCodeServedContextMinimum = 65_536

    public struct Assessment: Equatable, Sendable {
        public let disclosures: [String]
        public let permitsEnable: Bool
        public let automaticCodeOffer: Bool
        public let boundSeat: ModelDefinition?
        public let refusal: String?

        public init(
            disclosures: [String],
            permitsEnable: Bool,
            automaticCodeOffer: Bool,
            boundSeat: ModelDefinition?,
            refusal: String?
        ) {
            self.disclosures = disclosures
            self.permitsEnable = permitsEnable
            self.automaticCodeOffer = automaticCodeOffer
            self.boundSeat = boundSeat
            self.refusal = refusal
        }
    }

    /// Explicit enable of a discovered local tag onto one agent body.
    /// Never refuses on provenance, G1, or served context.
    public static func assessExplicitEnable(
        candidate: ModelDefinition,
        bodyDriverId: String,
        g1Passed: Bool?,
        servedContextWindow: Int?
    ) -> Assessment {
        guard allowedBodies.contains(bodyDriverId) else {
            return Assessment(
                disclosures: [],
                permitsEnable: false,
                automaticCodeOffer: false,
                boundSeat: nil,
                refusal: "unknown agent body '\(bodyDriverId)' — choose claude_code or opencode at enable"
            )
        }
        let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: candidate.modelLabel)
            ?? candidate.displayName
        var seat = candidate
        seat.driverId = bodyDriverId
        seat.id = OllamaLocalModelDiscoveryProvider.seatedID(tag: tag, bodyDriverId: bodyDriverId)
        seat.origin = .discovered
        seat.defaultEnabled = false
        seat.updatedAt = Date()

        var disclosures: [String] = []
        disclosures.append(
            "\(seat.displayName) runs on your Mac through Ollama. Allnighter is adding it to \(bodyDisplayName(bodyDriverId))."
        )
        if g1Passed == false {
            disclosures.append(LocalRuntimeAdvisory.g1Failed)
        } else if g1Passed != true {
            disclosures.append(LocalRuntimeAdvisory.g1Unknown)
        }
        if let servedContextWindow, servedContextWindow < automaticCodeServedContextMinimum {
            disclosures.append(LocalRuntimeAdvisory.servedWindowBelowFloor(servedContextWindow))
        }

        return Assessment(
            disclosures: disclosures,
            permitsEnable: true,
            automaticCodeOffer: allowsAutomaticCodeOffer(
                g1Passed: g1Passed,
                servedContextWindow: servedContextWindow
            ),
            boundSeat: seat,
            refusal: nil
        )
    }

    /// What we volunteer as a Code seat — not what we permit on explicit pin.
    public static func allowsAutomaticCodeOffer(
        g1Passed: Bool?,
        servedContextWindow: Int?
    ) -> Bool {
        g1Passed == true
            && (servedContextWindow ?? 0) >= automaticCodeServedContextMinimum
    }

    private static func bodyDisplayName(_ bodyDriverId: String) -> String {
        switch bodyDriverId {
        case "opencode": return "OpenCode"
        case "claude_code": return "Claude Code"
        default: return bodyDriverId
        }
    }
}
