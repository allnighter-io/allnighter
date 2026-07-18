import Foundation
import AllnighterCore

/// Per-thread advisory `flock(2)` for cross-process send serialization.
/// Released automatically when the handle is deallocated.
public final class ThreadFlockLock: @unchecked Sendable {
    public final class Handle: @unchecked Sendable {
        let fd: Int32
        init(fd: Int32) { self.fd = fd }
        deinit { flock(fd, LOCK_UN); close(fd) }
    }

    /// Blocking exclusive lock on `lockURL` (creates the file if needed).
    public static func acquire(lockURL: URL) throws -> Handle {
        // O_CLOEXEC (SR-11 / Sol F16): without it a worker subprocess spawned during the
        // brief attachment-store RMW inherits this fd, so the flock is not released on the
        // parent's close() until every such child exits — a latent cross-process wedge.
        // ExecutionLaneFlock got O_CLOEXEC in PO-F9; this flock family had been missed.
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AttachmentError.stageFailed }
        if flock(fd, LOCK_EX) != 0 {
            close(fd)
            throw AttachmentError.stageFailed
        }
        return Handle(fd: fd)
    }

    /// Non-blocking try; returns nil when another holder has the lock.
    public static func tryAcquire(lockURL: URL) -> Handle? {
        // O_CLOEXEC (SR-11 / Sol F16): without it a worker subprocess spawned during the
        // brief attachment-store RMW inherits this fd, so the flock is not released on the
        // parent's close() until every such child exits — a latent cross-process wedge.
        // ExecutionLaneFlock got O_CLOEXEC in PO-F9; this flock family had been missed.
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return Handle(fd: fd)
        }
        close(fd)
        return nil
    }
}
