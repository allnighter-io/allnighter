import SwiftUI

#if DEBUG
/// DEBUG GUI fixture routing helpers for `RootView`.
enum RootDebugRouting {
    struct ShellState {
        var showDevSettings: Bool
        var showComposeSpecimen: Bool
        var showReadiness: Bool
        var showDoctor: Bool
        var showTeamDropdown: Bool
        var readinessFocus: String?
    }

    static func navigate(
        to screen: DevGUIScreen,
        scenario: String?,
        devBenchScenario: String?,
        state: inout ShellState,
        applyScenario: (String) -> Void,
        resetSetupCompleted: () -> Void
    ) {
        state.showDevSettings = false
        state.showComposeSpecimen = false
        if let scenario { applyScenario(scenario) }
        switch screen {
        case .compose:
            state.showReadiness = false
            state.showDoctor = false
            state.showTeamDropdown = false
        case .routingComposer:
            state.showReadiness = false
            state.showDoctor = false
            state.showTeamDropdown = false
            state.showComposeSpecimen = true
        case .teamDropdown:
            state.showReadiness = false
            state.showDoctor = false
            state.showTeamDropdown = true
        case .cliSetupPopover:
            state.showReadiness = false
            state.showTeamDropdown = false
            state.showDoctor = true
        case .cliSetupPage:
            state.showTeamDropdown = false
            state.showDoctor = false
            state.readinessFocus = GUIFixture.readinessFocusDriverId(for: scenario ?? devBenchScenario)
            state.showReadiness = true
        case .firstRunOnboarding:
            resetSetupCompleted()
            state.showTeamDropdown = false
            state.showDoctor = false
            state.readinessFocus = GUIFixture.readinessFocusDriverId(for: scenario ?? devBenchScenario)
            state.showReadiness = true
        }
    }
}
#endif
