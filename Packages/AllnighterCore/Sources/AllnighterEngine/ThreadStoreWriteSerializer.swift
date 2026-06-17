import Foundation

/// Per-root synchronous mutation lane shared by all `ThreadStore` values that
/// point at the same canonical `rootDirectory`.
enum ThreadStoreWriteSerializer {
    private final class Lane: @unchecked Sendable {
        let queue = DispatchQueue(label: "com.allnighter.threadstore.write")
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var lanes: [String: Lane] = [:]

        func synchronized<T>(rootDirectory: URL, _ body: () throws -> T) rethrows -> T {
            let key = rootDirectory.standardizedFileURL.path
            let lane: Lane
            lock.lock()
            if let existing = lanes[key] {
                lane = existing
            } else {
                let created = Lane()
                lanes[key] = created
                lane = created
            }
            lock.unlock()
            return try lane.queue.sync(execute: body)
        }
    }

    private static let registry = Registry()

    static func synchronized<T>(rootDirectory: URL, _ body: () throws -> T) rethrows -> T {
        try registry.synchronized(rootDirectory: rootDirectory, body)
    }
}
