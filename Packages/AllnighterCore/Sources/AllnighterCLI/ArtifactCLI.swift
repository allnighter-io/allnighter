import Foundation
import AllnighterCore
import AllnighterEngine

enum ArtifactCLI {
  /// `alln artifact export <run-id|latest> --out <path> [--json]`
  static func runExport(_ args: [String], runtime: ToolRuntime) {
    let opts = Options(args)
    guard let out = opts.value("out"), !out.isEmpty else {
      AllnighterCLI.fail(
        code: "CLI_USAGE_ERROR",
        message: "usage: alln artifact export <run-id|latest> --out <path> [--json]"
      )
    }
    let (run, context) = terminalRun(
      ref: opts.positional.first ?? "latest",
      runtime: runtime,
      verb: "export"
    )
    let destination = URL(
      fileURLWithPath: (out as NSString).expandingTildeInPath,
      isDirectory: false
    )
    let store = RunStore()
    let runDir = try? store.runDirectory(forRunId: run.id)
    do {
      let htmlURL = try ArtifactWriter.exportHTML(
        run: run,
        destination: destination,
        reproduceCommand: TeamRunReplayCommand.build(from: run),
        context: context,
        runDirectory: runDir
      )
      emitResult(path: htmlURL.path, runId: run.id, json: opts.flag("json"), noOpen: true)
    } catch {
      AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "could not export artifact: \(error)")
    }
  }

  /// `alln artifact show <run-id|latest> [--no-open] [--json]`
  static func runShow(_ args: [String], runtime: ToolRuntime) {
    let opts = Options(args)
    let (run, context) = terminalRun(
      ref: opts.positional.first ?? "latest",
      runtime: runtime,
      verb: "show"
    )
    let store = RunStore()
    guard let runDir = try? store.runDirectory(forRunId: run.id) else {
      AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "could not resolve run directory for \(run.id)")
    }
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

  private static func terminalRun(
    ref: String,
    runtime: ToolRuntime,
    verb: String
  ) -> (TeamRun, ArtifactProjector.Context) {
    guard let run = AllnighterCLI.resolveRun(ref) else {
      AllnighterCLI.failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
    }
    guard ArtifactProjector.canProject(run) else {
      AllnighterCLI.fail(
        code: "RUN_NOT_TERMINAL",
        message: "run \(run.id) is not terminal — artifact \(verb) requires a finished run"
      )
    }
    let context = ArtifactProjector.Context(models: runtime.models, manifests: runtime.registry.all)
    return (run, context)
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
