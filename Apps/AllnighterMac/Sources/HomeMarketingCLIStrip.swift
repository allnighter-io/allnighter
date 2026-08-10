import SwiftUI
import AllnighterCore

/// FLCS-S01 — marketing empty-state CLI chips. Pure projection over `setupCards`;
/// not capacity, not `composeBench` models.
enum HomeMarketingCLIStrip {
    /// Cards to paint as chips. `nil` means suppress the row (Find-my-team owns
    /// the never-scanned statement).
    static func visibleCards(
        from cards: [SetupCardModel],
        showsFindTeamFrame: Bool,
        cursorAppPresent: Bool = CursorAgentCLIInstall.isCursorAppInstalled()
    ) -> [SetupCardModel]? {
        if showsFindTeamFrame { return nil }
        let keepNotInstalledIds = Set(
            CLISetupGrouping.cursorInstallPromptCards(
                from: cards,
                cursorAppPresent: cursorAppPresent
            ).map(\.driverId)
        )
        let hasReady = cards.contains { $0.state == .ready }
        if hasReady {
            // Generic catalog absences stay hidden once any CLI is ready — except
            // Cursor when Cursor.app proves the product is already on this Mac.
            return cards.filter {
                $0.state != .notInstalled || keepNotInstalledIds.contains($0.driverId)
            }
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

    /// Cursor install-prompt seats are actionable attention, not dormant absences.
    static func dotKind(
        for card: SetupCardModel,
        cursorAppPresent: Bool = CursorAgentCLIInstall.isCursorAppInstalled()
    ) -> DotKind {
        let absent = card.state == .notInstalled || card.state == .notChecked
        if card.driverId == CursorAgentCLIInstall.driverId,
           CursorAgentCLIInstall.shouldPromptInstall(
            cliAbsentOrUnchecked: absent,
            cursorAppPresent: cursorAppPresent
           ) {
            return .attention
        }
        return dotKind(for: card.state)
    }

    @ViewBuilder
    static func statusDot(
        for card: SetupCardModel,
        cursorAppPresent: Bool = CursorAgentCLIInstall.isCursorAppInstalled()
    ) -> some View {
        switch dotKind(for: card, cursorAppPresent: cursorAppPresent) {
        case .ready:
            StatusDot(color: ALPalette.green500, halo: ALPalette.green500.opacity(0.15))
        case .attention:
            StatusDot(color: ALPalette.amber500, halo: ALPalette.amber500.opacity(0.18))
        case .dormant:
            StatusDot(color: ALPalette.ink450, halo: nil)
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
