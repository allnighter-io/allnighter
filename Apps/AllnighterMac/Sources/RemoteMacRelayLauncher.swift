import AllnighterCore
import Foundation

enum RemoteMacRelayLauncher {
    static func ensureRunning() async -> RemoteRelayLaunchState {
        guard RemoteSupabaseEnvironment.load() != nil else {
            return .failed("Sign in on this Mac first.")
        }

        guard let repoRoot = resolveRepoRoot() else {
            return .failed("Could not find the Allnighter repo to start the relay agent.")
        }

        let script = repoRoot.appendingPathComponent("scripts/ios_live_mac_agent.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .failed("Relay launcher script is missing from this build.")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [script.path, "ensure"]
                process.currentDirectoryURL = repoRoot

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .running)
                    } else {
                        continuation.resume(returning: .failed(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    static func stopIfRunning() {
        guard let repoRoot = resolveRepoRoot() else { return }
        let script = repoRoot.appendingPathComponent("scripts/ios_live_mac_agent.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "stop"]
        process.currentDirectoryURL = repoRoot
        try? process.run()
    }

    private static func resolveRepoRoot() -> URL? {
        if let configured = ProcessInfo.processInfo.environment["ALLNIGHTER_REPO_ROOT"] {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }

        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for _ in 0..<6 {
            let package = candidate.appendingPathComponent("Packages/AllnighterCore/Package.swift")
            if FileManager.default.fileExists(atPath: package.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}
