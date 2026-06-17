import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Proves per-root write serialization: separate `ThreadStore` values pointed at
/// the same root cannot lose concurrent read-modify-write mutations.
final class ThreadStoreConcurrencyTests: XCTestCase {

    private static let epoch = Date(timeIntervalSince1970: 1_000)

    private func freshRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("threadstore-concurrency-\(UUID().uuidString)")
    }

    private static func userTurn(_ id: String, threadId: String, createdAt: Date) -> ThreadTurn {
        ThreadTurn(
            id: id,
            threadId: threadId,
            kind: .userMessage,
            status: .done,
            createdAt: createdAt,
            author: .user,
            text: id
        )
    }

    func testConcurrentAppendFromSeparateStoresRetainsAllTurns() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storeA = ThreadStore(rootDirectory: root)
        let storeB = ThreadStore(rootDirectory: root)
        let epoch = Self.epoch
        _ = try storeA.create(id: "shared", title: "Shared", now: epoch)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<50 {
                    let turn = Self.userTurn("turn-a-\(i)", threadId: "shared", createdAt: epoch)
                    _ = try? storeA.appendTurn(turn, toThreadId: "shared", now: epoch.addingTimeInterval(Double(i)))
                }
            }
            group.addTask {
                for i in 0..<50 {
                    let turn = Self.userTurn("turn-b-\(i)", threadId: "shared", createdAt: epoch)
                    _ = try? storeB.appendTurn(turn, toThreadId: "shared", now: epoch.addingTimeInterval(Double(100 + i)))
                }
            }
        }

        let final = storeA.get("shared")
        XCTAssertEqual(final?.turns.count, 100)
        XCTAssertEqual(Set(final?.turns.map(\.id) ?? []).count, 100)
    }

    /// Concurrent save + load must never tear: the reader sees the complete old
    /// or complete new thread.json, never a corrupt decode. Guards atomic writes.
    func testConcurrentSaveAndLoadNeverReturnsCorruptThread() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ThreadStore(rootDirectory: root)
        let epoch = Self.epoch
        _ = try store.create(id: "concurrent-1", title: "Seed", now: epoch)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<300 {
                    guard var thread = store.get("concurrent-1") else { continue }
                    thread.title = "title-\(i % 64)"
                    thread.updatedAt = epoch.addingTimeInterval(Double(i))
                    _ = try? store.saveForImport(thread)
                }
            }
            group.addTask {
                for _ in 0..<300 {
                    let loaded = store.get("concurrent-1")
                    XCTAssertNotNil(loaded, "load saw a torn/partial thread.json — save must be atomic")
                    XCTAssertEqual(loaded?.id, "concurrent-1")
                }
            }
        }
    }

    func testConcurrentDuplicateTurnIdRejectedUnderSerialization() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storeA = ThreadStore(rootDirectory: root)
        let storeB = ThreadStore(rootDirectory: root)
        let epoch = Self.epoch
        _ = try storeA.create(id: "shared", title: "Shared", now: epoch)

        let duplicate = Self.userTurn("dup", threadId: "shared", createdAt: epoch)
        enum Outcome: Sendable {
            case success
            case duplicate
            case failure(String)
        }

        let outcomes = await withTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            for _ in 0..<40 {
                group.addTask {
                    let store: ThreadStore = Bool.random() ? storeA : storeB
                    do {
                        _ = try store.appendTurn(duplicate, toThreadId: "shared", now: epoch)
                        return .success
                    } catch let error as ThreadStoreError {
                        if error == .duplicateTurnId("dup") {
                            return .duplicate
                        }
                        return .failure("\(error)")
                    } catch {
                        return .failure("\(error)")
                    }
                }
            }
            var collected: [Outcome] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        let successes = outcomes.filter { if case .success = $0 { return true }; return false }.count
        let duplicateErrors = outcomes.filter { if case .duplicate = $0 { return true }; return false }.count
        let failures = outcomes.compactMap { if case .failure(let message) = $0 { return message }; return nil }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))

        XCTAssertEqual(successes, 1)
        XCTAssertEqual(duplicateErrors, 39)
        XCTAssertEqual(storeA.get("shared")?.turns.count, 1)
        XCTAssertEqual(storeA.get("shared")?.turns.first?.id, "dup")
    }
}
