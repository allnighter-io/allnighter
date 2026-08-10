import Foundation

@main
struct ServeLaunchdHarness {
    struct Heartbeat: Codable {
        var schemaVersion = 1
        var pid: Int32
        var startedAt: Date
        var beatAt: Date
        var beatCount: Int
        var cdhash: String
        var buildTag: String
        var argv0: String
        var cwd: String
        var path: String
    }

    static func getCdhash() -> String {
        // Path-derived via codesign, not image-derived. Use buildTag for in-image identity.
        let selfPath = CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dvvv", selfPath]
        let pipe = Pipe()
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CDHash=") {
                return String(trimmed.dropFirst(7))
            }
        }
        return "unknown"
    }

    static func makeHeartbeat(beatCount: Int, startedAt: Date) -> Heartbeat {
        Heartbeat(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            beatAt: Date(),
            beatCount: beatCount,
            cdhash: getCdhash(),
            buildTag: __harnessBuildTag,
            argv0: CommandLine.arguments[0],
            cwd: FileManager.default.currentDirectoryPath,
            path: ProcessInfo.processInfo.environment["PATH"] ?? ""
        )
    }

    static func writeBeat(_ heartbeat: Heartbeat, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(heartbeat) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: harness <heartbeat-path> <run|exit-zero|exit-nonzero>\n".utf8))
            Darwin.exit(1)
        }

        let heartbeatURL = URL(fileURLWithPath: args[0])
        let mode = args[1]

        switch mode {
        case "run":
            let startedAt = Date()
            var count = 0
            while true {
                count += 1
                writeBeat(makeHeartbeat(beatCount: count, startedAt: startedAt), to: heartbeatURL)
                sleep(1)
            }
        case "exit-zero":
            writeBeat(makeHeartbeat(beatCount: 1, startedAt: Date()), to: heartbeatURL)
            Darwin.exit(0)
        case "exit-nonzero":
            writeBeat(makeHeartbeat(beatCount: 1, startedAt: Date()), to: heartbeatURL)
            Darwin.exit(3)
        default:
            FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8))
            Darwin.exit(1)
        }
    }
}
