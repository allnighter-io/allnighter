import AllnighterCore

/// The GUI Factory Floor card's next moves (bug list #4): EXACTLY two composer-opening
/// actions — hand the synthesis to another team, or continue here with Auto. Save-to-Pending,
/// Draft, and Run-when-ready are intentionally absent (they were destinations, not actions).
/// Pure + a single source of truth so the rendered set is testable.
enum FloorNextMovePresenter {
    struct Move: Equatable {
        let kind: FloorNextAction.Kind
        let label: String
        let icon: String
        let primary: Bool
    }

    static let cardMoves: [Move] = [
        .init(kind: .askAnotherTeam, label: "Ask Another Team", icon: "person.2", primary: true),
        .init(kind: .continueWithAuto, label: "Continue with Auto", icon: "infinity", primary: false),
    ]
}
