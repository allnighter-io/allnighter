import AppKit
import AllnighterCore
import AgentOSTeam
import AllnighterEngine

/// TRR-S01b/S01c — regenerate artifact HTML via shared Core writer, open in default browser.
enum ArtifactFloorOpener {
  static func openArtifact(for run: TeamRun, models: [Model] = []) {
    guard ArtifactProjector.canProject(run) else {
      presentFailure("Run is not terminal — artifact requires a finished run.")
      return
    }
    do {
      let runDir = try RunStore().runDirectory(forRunId: run.id)
      let url = try ArtifactWriter.writeHTML(
        run: run,
        runDirectory: runDir,
        reproduceCommand: TeamRunReplayCommand.build(from: run),
        context: .init(models: models)
      )
      guard NSWorkspace.shared.open(url) else {
        presentFailure("Could not open the artifact in your browser:\n\(url.path)")
        return
      }
    } catch {
      presentFailure(message(for: error))
    }
  }

  static func regenerateArtifact(for run: TeamRun, models: [Model]) {
    guard ArtifactProjector.canProject(run) else { return }
    do {
      let runDir = try RunStore().runDirectory(forRunId: run.id)
      try ArtifactWriter.writeHTML(
        run: run,
        runDirectory: runDir,
        reproduceCommand: TeamRunReplayCommand.build(from: run),
        context: .init(models: models)
      )
    } catch {
      // Best-effort — Open artifact will retry on demand.
    }
  }

  private static func message(for error: Error) -> String {
    if let write = error as? ArtifactWriter.WriteError {
      switch write {
      case .notTerminal:
        return "Run is not terminal — artifact requires a finished run."
      case .writeFailed(let reason):
        return "Could not write artifact/index.html.\n\(reason)"
      }
    }
    return "Could not open artifact: \(error.localizedDescription)"
  }

  private static func presentFailure(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Open artifact failed"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
