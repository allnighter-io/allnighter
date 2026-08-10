import SwiftUI

/// FLCS-S01 — marketing empty-state CLI chips. Pure projection over `setupCards`;
/// not capacity, not `composeBench` models.
enum HomeMarketingCLIStrip {
    /// Cards to paint as chips. `nil` means suppress the row (Find-my-team owns
    /// the never-scanned statement).
    static func visibleCards(
        from cards: [SetupCardModel],
        showsFindTeamFrame: Bool
    ) -> [SetupCardModel]? {
        if showsFindTeamFrame { return nil }
        let hasReady = cards.contains { $0.state == .ready }
        if hasReady {
            return cards.filter { $0.state != .notInstalled }
        }
        return cards
    }

    /// Fold `SetupCardState` → StatusDot kind (packet fold table).
    enum DotKind: Equatable {
        case ready
        case attention
        case dormant
    }

    static func dotKind(for state: SetupCardState) -> DotKind {
        switch state {
        case .ready:
            return .ready
        case .notInstalled, .notChecked, .parked:
            return .dormant
        case .needsLogin, .needsPath, .probeFailed, .rateLimited,
             .installedNotProbed, .detecting, .reprobing, .queued, .waiting:
            return .attention
        }
    }

    @ViewBuilder
    static func statusDot(for state: SetupCardState) -> some View {
        switch dotKind(for: state) {
        case .ready:
            StatusDot(color: ALPalette.green500, halo: ALPalette.green500.opacity(0.15))
        case .attention:
            StatusDot(color: ALPalette.amber500, halo: ALPalette.amber500.opacity(0.18))
        case .dormant:
            StatusDot(color: ALPalette.ink450, halo: nil)
        }
    }
}
