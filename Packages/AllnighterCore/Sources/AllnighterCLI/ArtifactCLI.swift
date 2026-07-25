import Foundation
import AllnighterCore
import AllnighterEngine

enum ArtifactCLI {
  /// `alln artifact show <run-id|latest> [--no-open] [--json]`
  static func runShow(_ args: [String], runtime: ToolRuntime) {
    let opts = Options(args)
    let ref = opts.positional.first ?? "latest"
    guard let run = AllnighterCLI.resolveRun(ref) else {
      AllnighterCLI.failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
    }
    guard ArtifactProjector.canProject(run) else {
      AllnighterCLI.fail(
        code: "RUN_NOT_TERMINAL",
        message: "run \(run.id) is not terminal — artifact show requires a finished run"
      )
    }

    let store = RunStore()
    guard let runDir = try? store.runDirectory(forRunId: run.id) else {
      AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "could not resolve run directory for \(run.id)")
    }
    let context = ArtifactProjector.Context(models: runtime.models, manifests: runtime.registry.all)
    do {
      let htmlURL = try ArtifactWriter.writeHTML(
        run: run,
        runDirectory: runDir,
        reproduceCommand: TeamRunReplayCommand.build(from: run),
        context: context
      )
      emitResult(path: htmlURL.path, runId: run.id, json: opts.flag("json"), noOpen: opts.flag("no-open"))
    } catch {
      AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "could not write artifact: \(error)")
    }
  }

  private static func emitResult(path: String, runId: String, json: Bool, noOpen: Bool) {
    if json {
      let payload: [String: String] = [
        "runId": runId,
        "path": path,
        "honesty": ArtifactProjector.honesty,
      ]
      print(AllnighterCLI.jsonString(payload))
      return
    }
    print(path)
    guard !noOpen else { return }
    #if os(macOS)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [path]
    try? task.run()
    #endif
  }
}
