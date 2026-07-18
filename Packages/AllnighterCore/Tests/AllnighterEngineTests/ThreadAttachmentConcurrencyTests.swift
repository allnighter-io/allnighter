import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Concurrent attachment index writes must not tear JSON (CIA-S00b).
final class ThreadAttachmentConcurrencyTests: XCTestCase {

    private func tinyPNG() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 2, height: 2,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testConcurrentDraftIngestsRetainAllDrafts() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("attc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ThreadAttachmentStore(threadDirectory: dir)
        let now = Date(timeIntervalSince1970: 0)
        let group = DispatchGroup()
        let lock = NSLock()
        var errors: [Error] = []

        for i in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let handle = try ThreadFlockLock.acquire(lockURL: store.lockURL)
                    defer { _ = handle }
                    _ = try store.ingestDraft(
                        data: self.tinyPNG(), threadId: "t1", sourceKind: .paste,
                        draftId: "d\(i)", now: now
                    )
                } catch {
                    lock.lock(); errors.append(error); lock.unlock()
                }
            }
        }
        group.wait()
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(store.loadDraftIndex().drafts.count, 4)
    }

    /// SR-11 (Sol F16): the ThreadFlockLock fd must be close-on-exec, or a worker subprocess
    /// spawned while the lock is held inherits it and the flock is not released on the
    /// parent's `close()` until every such child exits. Assert the flag is set on the fd.
    func testThreadFlockLockFdIsCloseOnExec() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-flock-cloexec-\(UUID().uuidString).lock")
        let handle = try ThreadFlockLock.acquire(lockURL: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let flags = fcntl(handle.fd, F_GETFD)
        XCTAssertNotEqual(flags, -1, "F_GETFD failed")
        XCTAssertEqual(flags & FD_CLOEXEC, FD_CLOEXEC, "ThreadFlockLock fd must have FD_CLOEXEC set")
    }
}
