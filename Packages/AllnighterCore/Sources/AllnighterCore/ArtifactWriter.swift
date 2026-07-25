import Foundation
import AgentOSTeam

/// Writes the regenerable team artifact HTML under a run journal directory (TRR-S01/S01b).
public enum ArtifactWriter {
  public enum WriteError: Error, Equatable, CustomStringConvertible {
    case notTerminal
    /// Filesystem write failed; associated string is the underlying reason.
    case writeFailed(String)

    public var description: String {
      switch self {
      case .notTerminal:
        return "run is not terminal"
      case .writeFailed(let reason):
        return "could not write artifact HTML: \(reason)"
      }
    }
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
    let html = renderedHTML(run: run, reproduceCommand: reproduceCommand, context: context)
    let artifactDir = runDirectory.appendingPathComponent("artifact", isDirectory: true)
    do {
      try fileManager.createDirectory(at: artifactDir, withIntermediateDirectories: true)
      let htmlURL = artifactDir.appendingPathComponent("index.html")
      try Data(html.utf8).write(to: htmlURL, options: .atomic)
      return htmlURL
    } catch let error as WriteError {
      throw error
    } catch {
      throw WriteError.writeFailed(error.localizedDescription)
    }
  }

  /// Writes the same self-contained HTML as `writeHTML` to a user-chosen path (TRR-S03).
  public static func exportHTML(
    run: TeamRun,
    destination: URL,
    reproduceCommand: String,
    context: ArtifactProjector.Context = .init(),
    fileManager: FileManager = .default
  ) throws -> URL {
    guard ArtifactProjector.canProject(run) else { throw WriteError.notTerminal }
    let html = renderedHTML(run: run, reproduceCommand: reproduceCommand, context: context)
    do {
      let parent = destination.deletingLastPathComponent()
      if !parent.path.isEmpty && parent.path != "/" {
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      }
      try Data(html.utf8).write(to: destination, options: .atomic)
      return destination
    } catch let error as WriteError {
      throw error
    } catch {
      throw WriteError.writeFailed(error.localizedDescription)
    }
  }

  private static func renderedHTML(
    run: TeamRun,
    reproduceCommand: String,
    context: ArtifactProjector.Context
  ) -> String {
    let card = ArtifactProjector.project(
      run,
      reproduceCommand: reproduceCommand,
      context: context
    )
    return ArtifactProjector.renderHTML(card)
  }
}
