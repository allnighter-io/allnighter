import XCTest

/// Mirrors `scripts/check.sh` ThreadStore caller allowlist (TSH-S06).
final class ThreadStoreCallerAuditTests: XCTestCase {

    func testAppSourcesDoNotCallSaveForImport() throws {
        let apps = repoRoot().appendingPathComponent("Apps")
        let hits = try swiftFiles(under: apps).flatMap { url in
            let source = try String(contentsOf: url, encoding: .utf8)
            return source.contains(".saveForImport(") ? [url.path] : []
        }
        XCTAssertTrue(hits.isEmpty, "Apps/ must not call ThreadStore.saveForImport:\n" + hits.joined(separator: "\n"))
    }

    func testAppSourcesDoNotCallTestPersistCursor() throws {
        let apps = repoRoot().appendingPathComponent("Apps")
        let hits = try swiftFiles(under: apps).flatMap { url in
            let source = try String(contentsOf: url, encoding: .utf8)
            return source.contains("testPersistCursor") ? [url.path] : []
        }
        XCTAssertTrue(hits.isEmpty, "Apps/ must not call ThreadStore test cursor hooks:\n" + hits.joined(separator: "\n"))
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
