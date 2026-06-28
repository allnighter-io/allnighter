import Foundation

/// Per-root synchronous mutation lane shared by all `ThreadStore` values that
/// point at the same canonical `rootDirectory`.
///
/// **Reentrancy:** callers must not invoke `synchronized` for the same root from
/// within an in-flight `synchronized` body on that root — nested `DispatchQueue.sync`
/// deadlocks. Reentrant entry is detected via a per-lane queue-specific key and
/// trapped with `preconditionFailure` (tests use `synchronizedForTesting` to catch
/// `WriteSerializerError.reentrantSynchronized` instead).
enum ThreadStoreWriteSerializer {
    enum WriteSerializerError: Error, Equatable {
        case reentrantSynchronized
    }

    private final class Lane: @unchecked Sendable {
        private let onQueueKey = DispatchSpecificKey<UInt8>()
        let queue: DispatchQueue

        init() {
            queue = DispatchQueue(label: "com.allnighter.threadstore.write")
            queue.setSpecific(key: onQueueKey, value: 1)
        }

        func synchronized<T>(_ body: () throws -> T) rethrows -> T {
            if DispatchQueue.getSpecific(key: onQueueKey) != nil {
                preconditionFailure(
                    "ThreadStoreWriteSerializer.synchronized reentered for the same root — nested DispatchQueue.sync deadlocks"
                )
            }
            return try queue.sync(execute: body)
        }

        #if DEBUG
        func synchronizedThrowingOnReentrancy<T>(_ body: () throws -> T) throws -> T {
            if DispatchQueue.getSpecific(key: onQueueKey) != nil {
                throw WriteSerializerError.reentrantSynchronized
            }
            return try queue.sync(execute: body)
        }
        #endif
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var lanes: [String: Lane] = [:]

        private func lane(for rootDirectory: URL) -> Lane {
            let key = rootDirectory.standardizedFileURL.path
            lock.lock()
            defer { lock.unlock() }
            if let existing = lanes[key] {
                return existing
            }
            let created = Lane()
            lanes[key] = created
            return created
        }

        func synchronized<T>(rootDirectory: URL, _ body: () throws -> T) rethrows -> T {
            try lane(for: rootDirectory).synchronized(body)
        }

        #if DEBUG
        func synchronizedForTesting<T>(rootDirectory: URL, _ body: () throws -> T) throws -> T {
            try lane(for: rootDirectory).synchronizedThrowingOnReentrancy(body)
        }
        #endif
    }

    private static let registry = Registry()

    static func synchronized<T>(rootDirectory: URL, _ body: () throws -> T) rethrows -> T {
        try registry.synchronized(rootDirectory: rootDirectory, body)
    }

    #if DEBUG
    static func synchronizedForTesting<T>(rootDirectory: URL, _ body: () throws -> T) throws -> T {
        try registry.synchronizedForTesting(rootDirectory: rootDirectory, body)
    }
    #endif
}
