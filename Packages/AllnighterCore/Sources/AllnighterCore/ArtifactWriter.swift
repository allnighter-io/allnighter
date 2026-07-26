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
  /// Copies design-board mockup PNGs into `artifact/mockups/` for self-contained reading.
  public static func writeHTML(
    run: TeamRun,
    runDirectory: URL,
    reproduceCommand: String,
    context: ArtifactProjector.Context = .init(),
    fileManager: FileManager = .default
  ) throws -> URL {
    guard ArtifactProjector.canProject(run) else { throw WriteError.notTerminal }
    let artifactDir = runDirectory.appendingPathComponent("artifact", isDirectory: true)
    do {
      try fileManager.createDirectory(at: artifactDir, withIntermediateDirectories: true)
      let mockupRelSrc = try copyMockups(
        run: run,
        runDirectory: runDirectory,
        destinationDir: artifactDir.appendingPathComponent("mockups", isDirectory: true),
        fileManager: fileManager
      )
      let html = renderedHTML(
        run: run,
        reproduceCommand: reproduceCommand,
        context: context,
        runDirectory: runDirectory,
        mockupRelSrc: mockupRelSrc
      )
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
    runDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) throws -> URL {
    guard ArtifactProjector.canProject(run) else { throw WriteError.notTerminal }
    do {
      let parent = destination.deletingLastPathComponent()
      if !parent.path.isEmpty && parent.path != "/" {
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      }
      var mockupRelSrc: [String: String] = [:]
      if let runDirectory {
        mockupRelSrc = try copyMockups(
          run: run,
          runDirectory: runDirectory,
          destinationDir: parent.appendingPathComponent("mockups", isDirectory: true),
          fileManager: fileManager
        )
      }
      let html = renderedHTML(
        run: run,
        reproduceCommand: reproduceCommand,
        context: context,
        runDirectory: runDirectory,
        mockupRelSrc: mockupRelSrc
      )
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
    context: ArtifactProjector.Context,
    runDirectory: URL?,
    mockupRelSrc: [String: String]
  ) -> String {
    let card = ArtifactProjector.project(
      run,
      reproduceCommand: reproduceCommand,
      context: context,
      runDirectory: runDirectory,
      mockupRelSrc: mockupRelSrc
    )
    return ArtifactProjector.renderHTML(card)
  }

  /// Copies board option images into `destinationDir`; returns workerId → `mockups/<file>`.
  private static func copyMockups(
    run: TeamRun,
    runDirectory: URL,
    destinationDir: URL,
    fileManager: FileManager
  ) throws -> [String: String] {
    guard let board = run.latestStage(.board)?.payload?.board else { return [:] }
    var map: [String: String] = [:]
    let options = board.options.filter { $0.imagePath != nil }
    guard !options.isEmpty else { return [:] }
    try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
    for opt in options {
      guard let rel = opt.imagePath else { continue }
      let src = runDirectory.appendingPathComponent(rel)
      guard fileManager.fileExists(atPath: src.path) else { continue }
      let name = src.lastPathComponent
      let dst = destinationDir.appendingPathComponent(name)
      if fileManager.fileExists(atPath: dst.path) {
        try fileManager.removeItem(at: dst)
      }
      try fileManager.copyItem(at: src, to: dst)
      map[opt.workerId] = "mockups/\(name)"
    }
    return map
  }
}
