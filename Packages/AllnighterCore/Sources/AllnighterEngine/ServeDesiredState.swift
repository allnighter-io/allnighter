import Foundation
import AllnighterCore

public enum ServeDesiredState {

    public enum State: String, Codable, Sendable, Equatable {
        case enabled
        case disabled
    }

    public enum Reading: Equatable, Sendable {
        case absent
        case present(state: State, updatedAt: Date)
        case unreadable(reason: String)

        public var effectiveState: State {
            switch self {
            case .absent, .unreadable:
                return .enabled
            case .present(let state, _):
                return state
            }
        }
    }

    public struct Failure: Error, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    private struct Record: Codable {
        let schemaVersion: Int
        let state: State
        let updatedAt: Date
    }

    private static let currentSchemaVersion = 1

    public static func storeURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Allnighter", isDirectory: true)
            .appendingPathComponent("serve-desired-state.json")
    }

    public static func read(
        homeDirectory: URL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = { Date() }
    ) -> Reading {
        let url = storeURL(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            return .absent
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unreadable(reason: "file exists but cannot be read")
        }
        guard let record = try? CoreJSON.decode(Record.self, from: data) else {
            return .unreadable(reason: "corrupt or truncated JSON")
        }
        guard record.schemaVersion <= currentSchemaVersion else {
            return .unreadable(reason: "future schema version \(record.schemaVersion) > current \(currentSchemaVersion)")
        }
        return .present(state: record.state, updatedAt: record.updatedAt)
    }

    public static func write(
        _ state: State,
        homeDirectory: URL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = { Date() }
    ) -> Result<Void, Failure> {
        let url = storeURL(homeDirectory: homeDirectory)
        let record = Record(schemaVersion: currentSchemaVersion, state: state, updatedAt: clock())
        let parent = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            return .failure(Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED",
                                    message: "could not create directory \(parent.path): \(error.localizedDescription)"))
        }

        let encoded: Data
        do {
            encoded = try CoreJSON.encode(record)
        } catch {
            return .failure(Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED",
                                    message: "encoding failed: \(error.localizedDescription)"))
        }

        let tempURL = parent.appendingPathComponent(".serve-desired-state.staging.\(UUID().uuidString)")
        do {
            try encoded.write(to: tempURL, options: .atomic)
        } catch {
            return .failure(Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED",
                                    message: "temp write failed: \(error.localizedDescription)"))
        }

        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tempURL, to: url)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return .failure(Failure(code: "SERVE_DESIRED_STATE_WRITE_FAILED",
                                    message: "rename to \(url.path) failed: \(error.localizedDescription)"))
        }

        return .success(())
    }
}
