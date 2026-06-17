#if DEBUG
import SwiftUI
import AllnighterCore

/// DEBUG-only GUI route catalog — jump to any built surface; optional bench scenario.
enum DevGUIScreen: String, CaseIterable, Identifiable {
    case compose
    case teamDropdown
    case cliSetupPopover
    case cliSetupPage
    case firstRunOnboarding
    case routingComposer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compose: return "Home / compose"
        case .teamDropdown: return "Team dropdown"
        case .cliSetupPopover: return "CLI setup popover"
        case .cliSetupPage: return "CLI setup page"
        case .firstRunOnboarding: return "First-run onboarding"
        case .routingComposer: return "Routing composer (specimen)"
        }
    }
}

struct DevSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var activeScenario: String?
    var onUseLiveProbes: () -> Void
    var onNavigate: (DevGUIScreen, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    liveSection
                    navigateSection
                    scenarioSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 440, maxHeight: 620)
        .background(ALColor.base)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.accentText)
                Text("GUI routes")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
            }
            Spacer()
            if activeScenario != nil {
                Badge(text: "sim", tone: .warning, dot: true, mono: true)
            }
            IconButton(systemImage: "xmark", accessibilityLabel: "Close", small: true) { dismiss() }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Bench data")
            Text("Simulated health is DEBUG-only and never saved. Re-check all uses live probes and clears sim.")
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onUseLiveProbes) {
                Label("Use live cached probes", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.alSecondary(small: true))
        }
    }

    private var navigateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Open (current bench state)")
            ForEach(DevGUIScreen.allCases) { screen in
                routeButton(screen.label) { onNavigate(screen, nil) }
            }
        }
    }

    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Open with mixed-health scenario")
            ForEach(GUIFixture.benchScenarios, id: \.id) { scenario in
                VStack(alignment: .leading, spacing: 6) {
                    Text(scenario.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ALColor.textMuted)
                    HStack(spacing: 6) {
                        miniRoute("Team") { onNavigate(.teamDropdown, scenario.id) }
                        miniRoute("Popover") { onNavigate(.cliSetupPopover, scenario.id) }
                        miniRoute("Page") { onNavigate(.cliSetupPage, scenario.id) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold)).tracking(1.1)
            .foregroundStyle(ALColor.textFaint)
    }

    private func routeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11))
            }
            .foregroundStyle(ALColor.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func miniRoute(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.alGhost)
    }
}
#endif
