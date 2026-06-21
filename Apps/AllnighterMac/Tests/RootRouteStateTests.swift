import XCTest
@testable import AllnighterMac

/// The top-bar Inbox/Teams controls are route commands that must ESCAPE deep surfaces
/// (Factory Floor, Settings/Team Studio, Pending, Readiness, overlays) — even when the
/// target workspace is already selected. (This is the navigation-state proof the bug list
/// asks for; the founder's wall test remains the visual acceptance.)
final class RootRouteStateTests: XCTestCase {

    func testInboxDismissesFactoryFloorEvenWhenAlreadyInbox() {
        // The reported case: Inbox already selected, Floor open over it.
        let state = RootRouteState(
            workspaceMode: .inbox, floorOpen: true, showPending: false,
            showTeamStudio: false, showReadiness: false, showDoctor: false, showTeamDropdown: false)
        let routed = state.routed(to: .inbox)
        XCTAssertFalse(routed.floorOpen, "pressing Inbox closes the Floor even when Inbox is already selected")
        XCTAssertEqual(routed.workspaceMode, .inbox)
        XCTAssertFalse(routed.anyDeepSurfaceOpen)
    }

    func testTeamsFromFactoryFloorShowsTeamsLauncher() {
        let state = RootRouteState(
            workspaceMode: .inbox, floorOpen: true, showPending: false,
            showTeamStudio: false, showReadiness: false, showDoctor: false, showTeamDropdown: false)
        let routed = state.routed(to: .teams)
        XCTAssertEqual(routed.workspaceMode, .teams, "Teams shows the launcher")
        XCTAssertFalse(routed.floorOpen, "and the Floor yields")
    }

    func testRoutingDismissesSettingsPendingReadinessAndOverlays() {
        let state = RootRouteState(
            workspaceMode: .teams, floorOpen: false, showPending: true,
            showTeamStudio: true, showReadiness: true, showDoctor: true, showTeamDropdown: true)
        for target in [WorkspaceMode.inbox, .teams] {
            let routed = state.routed(to: target)
            XCTAssertEqual(routed.workspaceMode, target)
            XCTAssertFalse(routed.anyDeepSurfaceOpen,
                           "every deep surface dismissed when routing to \(target.label)")
        }
    }

    func testNoOpClearsDeepSurfacesButKeepsMode() {
        // Pressing the already-visible default route still closes deep surfaces and keeps
        // the workspace — it must not flip to the other workspace.
        let state = RootRouteState(
            workspaceMode: .inbox, floorOpen: false, showPending: true,
            showTeamStudio: false, showReadiness: false, showDoctor: false, showTeamDropdown: false)
        let routed = state.routed(to: .inbox)
        XCTAssertEqual(routed.workspaceMode, .inbox)
        XCTAssertFalse(routed.showPending)
    }
}
