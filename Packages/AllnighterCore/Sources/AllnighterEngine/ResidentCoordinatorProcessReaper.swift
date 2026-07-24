import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Conservative migration cleanup for pre-lock `alln serve` processes. It is
/// invoked only by the explicit install/restart path and never targets the PID
/// currently recorded by a healthy coordinator.
enum ResidentCoordinatorProcessReaper {
    struct Row: Equatable { var pid: Int32; var command: String }

    static func candidates(lines: String, preserving pid: Int32?) -> [Row] {
        lines.split(separator: "\n").compactMap { line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard let split = text.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let processID = Int32(text[..<split]) else { return nil }
            let command = text[split...].trimmingCharacters(in: .whitespaces)
            guard processID != pid,
                  command.contains("alln serve"),
                  !command.contains("alln serve install") else { return nil }
            return Row(pid: processID, command: command)
        }
    }

    static func reapExtras(preserving pid: Int32?) {
        let task = Foundation.Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        // Drain stdout BEFORE waitUntilExit(): `ps -ax` output on a busy machine can
        // exceed the pipe's 64KB kernel buffer, so `ps` blocks writing while we'd
        // block waiting for it to exit — a permanent deadlock (hung `alln serve
        // install` + hung test wall). Read to EOF first, same order as the other
        // `Process`/`Pipe` call sites (`GitObserver.runGitRaw`/`runGit`).
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        for process in candidates(lines: text, preserving: pid) { _ = kill(process.pid, SIGTERM) }
    }
}
