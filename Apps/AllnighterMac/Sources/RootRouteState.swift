import Foundation

/// The root navigation truth the top-bar Inbox/Teams commands operate on (the "one route
/// truth" the nav-escape spec asks for). A pure value type so the escape behavior is
/// unit-testable without hosting the SwiftUI view: routing to a workspace dismisses EVERY
/// deep surface above it (Factory Floor, Settings/Team Studio, Pending, Readiness, doctor
/// + dropdown overlays), even when that workspace is already selected.
struct RootRouteState: Equatable {
    var workspaceMode: WorkspaceMode
    var floorOpen: Bool
    var showPending: Bool
    var showTeamStudio: Bool
    var showReadiness: Bool
    var showDoctor: Bool
    var showTeamDropdown: Bool

    /// Any non-default surface sitting above the workspace.
    var anyDeepSurfaceOpen: Bool {
        floorOpen || showPending || showTeamStudio || showReadiness || showDoctor || showTeamDropdown
    }

    /// Route to `mode`, closing all deep surfaces. Pure — RootView applies the result.
    func routed(to mode: WorkspaceMode) -> RootRouteState {
        RootRouteState(
            workspaceMode: mode,
            floorOpen: false,
            showPending: false,
            showTeamStudio: false,
            showReadiness: false,
            showDoctor: false,
            showTeamDropdown: false
        )
    }
}
