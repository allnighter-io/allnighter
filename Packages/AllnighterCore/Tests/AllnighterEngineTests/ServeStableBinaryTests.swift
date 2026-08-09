import XCTest
import AllnighterEngine

final class ServeStableBinaryTests: XCTestCase {

    private var tempDir: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager()
        tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("alln-serve-stable-binary-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? fileManager.removeItem(at: tempDir)
        }
        tempDir = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    private func makeSource(name: String = "alln-fake", content: String = "#!/bin/sh\necho hi\n") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDestinationDir() -> URL {
        let dir = tempDir.appendingPathComponent("CLI", isDirectory: true)
        try! fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Copy, not symlink

    func testStageCopiesNotSymlinks() throws {
        let source = makeSource()
        let destDir = makeDestinationDir()
        let destURL = destDir.appendingPathComponent("alln")

        let result = ServeStableBinary.stage(from: source, to: destURL, fileManager: fileManager)
        guard case .success(let staging) = result else {
            XCTFail("expected success, got \(result)")
            return
        }

        XCTAssertEqual(staging.url, destURL)
        XCTAssertTrue(fileManager.fileExists(atPath: destURL.path))

        let sourceData = try Data(contentsOf: source)
        let destData = try Data(contentsOf: destURL)
        XCTAssertEqual(sourceData, destData, "copied content must match source")

        XCTAssertNil(try? fileManager.destinationOfSymbolicLink(atPath: destURL.path),
                     "destination must not be a symlink")
    }

    // MARK: - Overwrite updates content

    func testStageOverwriteUpdatesContent() throws {
        let source = makeSource(content: "#!/bin/sh\necho v2\n")
        let destDir = makeDestinationDir()
        let destURL = destDir.appendingPathComponent("alln")

        let oldBinary = makeSource(name: "old", content: "#!/bin/sh\necho v1\n")
        try fileManager.copyItem(at: oldBinary, to: destURL)

        let result = ServeStableBinary.stage(from: source, to: destURL, fileManager: fileManager)
        guard case .success(let staging) = result else {
            XCTFail("expected success, got \(result)")
            return
        }

        XCTAssertTrue(staging.bytesWereReplaced, "overwrite must report bytes were replaced")
        let destData = try Data(contentsOf: destURL)
        XCTAssertEqual(destData, try Data(contentsOf: source), "dest content must match new source after overwrite")
    }

    func testStageSameContentNoOverwrite() throws {
        let content = "#!/bin/sh\necho same\n"
        let source = makeSource(content: content)
        let destDir = makeDestinationDir()
        let destURL = destDir.appendingPathComponent("alln")

        try Data(content.utf8).write(to: destURL, options: .atomic)

        let result = ServeStableBinary.stage(from: source, to: destURL, fileManager: fileManager)
        guard case .success(let staging) = result else {
            XCTFail("expected success, got \(result)")
            return
        }

        XCTAssertFalse(staging.bytesWereReplaced, "identical content must report no replacement")
    }

    // MARK: - Executable bit

    func testStageSetsExecutableBit() throws {
        let source = makeSource()
        let destDir = makeDestinationDir()
        let destURL = destDir.appendingPathComponent("alln")

        let result = ServeStableBinary.stage(from: source, to: destURL, fileManager: fileManager)
        guard case .success = result else {
            XCTFail("expected success, got \(result)")
            return
        }

        XCTAssertTrue(fileManager.isExecutableFile(atPath: destURL.path),
                      "staged binary must be executable")
    }

    // MARK: - Default destination

    func testDefaultDestinationIsUnderApplicationSupport() {
        let dir = ServeStableBinary.defaultDestinationDirectory()
        let dirStr = dir.path
        XCTAssertTrue(dirStr.hasSuffix("/CLI") || dirStr.contains("/Allnighter/CLI"),
                      "default dest dir should be under Allnighter/CLI")
        let dest = ServeStableBinary.defaultDestinationURL()
        XCTAssertEqual(dest.lastPathComponent, "alln")
    }

    // MARK: - Failure: unreadable source

    func testUnreadableSourceFails() {
        let nonexistent = tempDir.appendingPathComponent("does-not-exist")
        let destURL = makeDestinationDir().appendingPathComponent("alln")
        let result = ServeStableBinary.stage(from: nonexistent, to: destURL, fileManager: fileManager)
        guard case .failure(let err) = result else {
            XCTFail("expected failure for unreadable source")
            return
        }
        XCTAssertEqual(err, .sourceNotReadable(nonexistent))
    }

    // MARK: - Failure: empty source

    func testEmptySourceFails() throws {
        let empty = makeSource(content: "")
        let destURL = makeDestinationDir().appendingPathComponent("alln")
        let result = ServeStableBinary.stage(from: empty, to: destURL, fileManager: fileManager)
        guard case .failure(let err) = result else {
            XCTFail("expected failure for empty source")
            return
        }
        if case .sourceDataEmpty = err {} else {
            XCTFail("expected sourceDataEmpty, got \(err)")
        }
    }
}
