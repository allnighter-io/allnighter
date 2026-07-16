import Foundation
import AllnighterCore

/// Suggested focus-brief scaffold for Panel rounds 2+ (`docs/phases/Pilot_Panel.md`
/// decision 6 / PN-S04). Includes the rejection-carry line and stance line so the
/// founder always knows which synthesis contract the session is in. Stances are
/// convention, never modes.
public enum PanelBriefScaffold {
    public static func template(round: Int) -> String {
        """
        # Panel focus brief — round \(round)

        <!-- stance: edit-in-place | propose-first -->

        <!-- Refuted last round: … — do not re-litigate -->

        <!-- focus: what this round should pressure-test -->

        <!-- out of scope: what seats must not chase -->

        """
    }

    /// Writes `brief-round<N>.md` into the panel's state folder.
    public static func writeRoundFile(
        panelId: String,
        round: Int = 1,
        stateStore: PanelStateStore = PanelStateStore()
    ) throws -> String {
        let directory = stateStore.rootDirectory
            .appendingPathComponent(panelId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("brief-round\(round).md")
        try template(round: round).write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
