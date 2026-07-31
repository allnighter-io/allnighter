import SwiftUI
import AppKit
import AllnighterCore

/// ATL-S04 live control on an open relay thread — Status (store-backed `LoopJSON`)
/// and Stop (`LoopCoordinator.stop`). Pilot must not appear in copy here.
struct RelayThreadChrome: View {
    @Environment(RelayStopController.self) private var relayStop
    @Environment(ThreadsViewModel.self) private var threads

    let loopId: String

    @State private var relayJSON: LoopJSON?
    @State private var statusPopoverOpen = false
    @State private var confirmStop = false

    var body: some View {
        // Must never be an empty view. This was a `Group` whose content was empty
        // while `relayJSON` was nil — so the lifecycle modifiers below, which are the
        // only thing that ever POPULATES `relayJSON`, had nothing to attach to and the
        // chrome could not escape its own empty state. Status and Stop never rendered,
        // in fixtures or in production. The zero-size sentinel keeps the view real so
        // `.task`/`.onAppear` reliably fire.
        HStack(spacing: 8) {
            Color.clear.frame(width: 0, height: 0)
            if let relayJSON {
                statusControl(relayJSON)
                if relayStop.canStop(loopId: loopId) {
                    stopButton
                }
            }
            if let error = relayStop.lastError[loopId] {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(ALPalette.red400)
                    .lineLimit(2)
            }
        }
        .task(id: loopId) { refreshStatus() }
        .onChange(of: threads.selectedThread?.turns.count) { _, _ in refreshStatus() }
        .onAppear {
            refreshStatus()
            if GUIFixture.opensRelayStopConfirm { confirmStop = true }
        }
        .confirmationDialog(
            "Stop this loop?",
            isPresented: $confirmStop,
            titleVisibility: .visible
        ) {
            Button(relayStop.isStopping(loopId) ? "Stopping…" : "Stop loop", role: .destructive) {
                performStop()
            }
            .disabled(relayStop.isStopping(loopId))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This loop will not resume. Work in flight is abandoned.")
        }
    }

    private var stopButton: some View {
        Button(relayStop.isStopping(loopId) ? "Stopping…" : "Stop") {
            confirmStop = true
        }
        .buttonStyle(.alLight)
        .disabled(relayStop.isStopping(loopId))
    }

    private func statusControl(_ json: LoopJSON) -> some View {
        Button {
            statusPopoverOpen.toggle()
        } label: {
            StatusPill(kind: Self.pillKind(for: json.status), label: Self.pillLabel(for: json.status))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $statusPopoverOpen, arrowEdge: .bottom) {
            RelayStatusPanel(json: json, loopId: loopId)
        }
    }

    private func refreshStatus() {
        relayJSON = RelayStatusLoader.loadLoopJSON(loopId: loopId)
    }

    private func performStop() {
        guard relayStop.stop(loopId: loopId) else { return }
        refreshStatus()
        threads.requestReload()
    }

    static func pillKind(for status: String) -> StatusPill.Kind {
        switch status {
        case "running", "escalated":
            return .running
        case "done":
            return .done
        case "stopped":
            return .failed
        case "awaitingPM":
            return .queued
        default:
            return .queued
        }
    }

    static func pillLabel(for status: String) -> String {
        switch status {
        case "running": return "Running"
        case "escalated": return "Escalated"
        case "done": return "Done"
        case "stopped": return "Stopped"
        case "awaitingPM": return "Awaiting PM"
        default: return status.capitalized
        }
    }
}

private struct RelayStatusPanel: View {
    let json: LoopJSON
    let loopId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loop status")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ALColor.textPrimary)
            RelayStatusFieldRow(label: "Status", value: json.status)
            RelayStatusFieldRow(label: "Rounds", value: "\(json.rounds)")
            if let note = json.note, !note.isEmpty {
                RelayStatusFieldRow(label: "Note", value: note)
            }
            if let stoppedReason = json.stoppedReason, !stoppedReason.isEmpty {
                RelayStatusFieldRow(label: "Stopped", value: stoppedReason)
            }
            if let pmTurn = json.pmTurn {
                RelayStatusFieldRow(label: "PM turn", value: pmTurn.reason)
                if let report = pmTurn.report, !report.isEmpty {
                    RelayStatusFieldRow(label: "Report", value: report)
                }
            }
            Button("Copy status command", action: copyStatusCommand)
                .buttonStyle(.alLight)
                .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(ALColor.raised)
    }

    private func copyStatusCommand() {
        let cmd = RelayStatusLoader.statusCommand(loopId: loopId)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }
}

private struct RelayStatusFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(ALColor.textFaint)
            Text(value)
                .font(ALFont.monoSm)
                .foregroundStyle(ALColor.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
