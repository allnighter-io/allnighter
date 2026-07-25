import Foundation
import AgentOSTeam

/// Writes the regenerable team artifact HTML under a run journal directory (TRR-S01/S01b).
public enum ArtifactWriter {
  public enum WriteError: Error, Equatable {
    case notTerminal
    case writeFailed
  }

  /// Regenerates `artifact/index.html` for a terminal run using `ArtifactProjector`.
  public static func writeHTML(
    run: TeamRun,
    runDirectory: URL,
    reproduceCommand: String,
    context: ArtifactProjector.Context = .init(),
    fileManager: FileManager = .default
  ) throws -> URL {
    guard ArtifactProjector.canProject(run) else { throw WriteError.notTerminal }
    let card = ArtifactProjector.project(
      run,
      reproduceCommand: reproduceCommand,
      context: context
    )
    let html = ArtifactProjector.renderHTML(card)
    let artifactDir = runDirectory.appendingPathComponent("artifact", isDirectory: true)
    do {
      try fileManager.createDirectory(at: artifactDir, withIntermediateDirectories: true)
      let htmlURL = artifactDir.appendingPathComponent("index.html")
      try Data(html.utf8).write(to: htmlURL, options: .atomic)
      return htmlURL
    } catch {
      throw WriteError.writeFailed
    }
  }
}
