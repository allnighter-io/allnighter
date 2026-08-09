import XCTest
@testable import AllnighterCore

final class AIReadinessShapeTests: XCTestCase {

    // MARK: - Detection

    func testEmptyDirectoryReturnsUnclear() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .unclear)
    }

    func testTypeScriptAppWithTSConfig() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("tsconfig.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .typeScriptAppOrMonorepo)
    }

    func testTypeScriptViaDependencyInPackageJson() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = #"{"dependencies":{"typescript":"^5.0.0"}}"#
        try pkg.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .typeScriptAppOrMonorepo)
    }

    func testSwiftAppleAppViaPackageDotSwift() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "// swift-tools-version:5.9".write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .swiftAppleApp)
    }

    func testSwiftAppleAppViaXcodeproj() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let projDir = tmp.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .swiftAppleApp)
    }

    func testSwiftAppleAppViaXcworkspace() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let wsDir = tmp.appendingPathComponent("MyApp.xcworkspace")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .swiftAppleApp)
    }

    func testConflictingSwiftAndTSReturnsUnclear() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "// swift-tools-version:5.9".write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("tsconfig.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .unclear)
    }

    func testCLIToolViaGoMod() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "module example.com/mytool".write(to: tmp.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .cliTool)
    }

    func testCLIToolViaCargoTomlBin() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "[package]\nname = \"mytool\"\n[[bin]]\nname = \"mytool\"".write(to: tmp.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .cliTool)
    }

    func testCLIToolViaMainGo() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "package main\nfunc main() {}".write(to: tmp.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .cliTool)
    }

    func testCLIToolViaMainSwift() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "print(\"hello\")".write(to: tmp.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .cliTool)
    }

    func testCLIToolViaPackageJsonBinNoTSConfig() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = #"{"bin":{"mytool":"./cli.js"}}"#
        try pkg.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .cliTool)
    }

    func testPackageJsonBinWithTSConfigIsTSNotCLI() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = #"{"bin":{"mytool":"./cli.js"}}"#
        try pkg.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("tsconfig.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .typeScriptAppOrMonorepo)
    }

    func testPackageJsonWithoutTSAndWithoutBinIsUnclear() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .unclear)
    }

    // MARK: - Injectable FS predicates

    func testInjectableSwiftAppleApp() {
        let root = URL(fileURLWithPath: "/tmp/fake")
        let fs: [String: String] = ["Package.swift": "// swift"]
        let exists: (String) -> Bool = { fs[$0] != nil }
        let contents: (String) throws -> String = { fs[$0]! }
        let entries: () throws -> [String] = { Array(fs.keys) }
        XCTAssertEqual(AIReadinessShape.detect(at: root, fileExists: exists, fileContents: contents, entryNames: entries), .swiftAppleApp)
    }

    func testInjectableTypeScript() {
        let root = URL(fileURLWithPath: "/tmp/fake")
        let fs: [String: String] = ["package.json": "{}", "tsconfig.json": "{}"]
        let exists: (String) -> Bool = { fs[$0] != nil }
        let contents: (String) throws -> String = { fs[$0]! }
        let entries: () throws -> [String] = { Array(fs.keys) }
        XCTAssertEqual(AIReadinessShape.detect(at: root, fileExists: exists, fileContents: contents, entryNames: entries), .typeScriptAppOrMonorepo)
    }

    func testInjectableConflict() {
        let root = URL(fileURLWithPath: "/tmp/fake")
        let fs: [String: String] = [
            "Package.swift": "// swift",
            "package.json": #"{"dependencies":{"typescript":"^5"}}"#,
            "tsconfig.json": "{}"
        ]
        let exists: (String) -> Bool = { fs[$0] != nil }
        let contents: (String) throws -> String = { fs[$0]! }
        let entries: () throws -> [String] = { Array(fs.keys) }
        XCTAssertEqual(AIReadinessShape.detect(at: root, fileExists: exists, fileContents: contents, entryNames: entries), .unclear)
    }

    func testInjectableCLITool() {
        let root = URL(fileURLWithPath: "/tmp/fake")
        let fs: [String: String] = ["go.mod": "module x"]
        let exists: (String) -> Bool = { fs[$0] != nil }
        let contents: (String) throws -> String = { fs[$0]! }
        let entries: () throws -> [String] = { Array(fs.keys) }
        XCTAssertEqual(AIReadinessShape.detect(at: root, fileExists: exists, fileContents: contents, entryNames: entries), .cliTool)
    }

    func testInjectableUnclear() {
        let root = URL(fileURLWithPath: "/tmp/fake")
        let fs: [String: String] = [:]
        let exists: (String) -> Bool = { fs[$0] != nil }
        let contents: (String) throws -> String = { fs[$0]! }
        let entries: () throws -> [String] = { Array(fs.keys) }
        XCTAssertEqual(AIReadinessShape.detect(at: root, fileExists: exists, fileContents: contents, entryNames: entries), .unclear)
    }

    // MARK: - Brief content

    func testBriefTypeScript() {
        let brief = AIReadinessShape.brief(for: .typeScriptAppOrMonorepo)
        XCTAssertTrue(brief.contains("script is *the* test"))
        XCTAssertTrue(brief.contains("Package manager truth"))
        XCTAssertTrue(brief.contains("Workspace graph"))
    }

    func testBriefSwiftAppleApp() {
        let brief = AIReadinessShape.brief(for: .swiftAppleApp)
        XCTAssertTrue(brief.contains("Simulator bootstrap"))
        XCTAssertTrue(brief.contains("Scheme discoverability"))
        XCTAssertTrue(brief.contains("SPM vs CocoaPods"))
        XCTAssertTrue(brief.contains("Build log"))
    }

    func testBriefCLITool() {
        let brief = AIReadinessShape.brief(for: .cliTool)
        XCTAssertTrue(brief.contains("Machine-readable output"))
        XCTAssertTrue(brief.contains("Teach-at-failure"))
        XCTAssertTrue(brief.contains("Cold PATH"))
        XCTAssertTrue(brief.contains("Invented-flag risk"))
    }

    func testBriefUnclear() {
        let brief = AIReadinessShape.brief(for: .unclear)
        XCTAssertTrue(brief.contains("unclear"))
        XCTAssertTrue(brief.contains("universal questions"))
        XCTAssertTrue(brief.contains("Packages/*/Package.swift") || brief.contains("nested"))
    }

    func testNestedPackagesMonorepoIsSwiftAppleApp() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Packages/AllnighterCore", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try "// swift-tools-version:5.9\n.executableTarget(".write(
            to: pkg.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let app = tmp.appendingPathComponent("Apps/AllnighterMac/AllnighterMac.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertEqual(AIReadinessShape.detect(at: tmp), .swiftAppleApp)
    }

    func testInjectableNestedPackageSwiftPath() {
        let fp = AIReadinessShape.detect(
            at: URL(fileURLWithPath: "/tmp/unused"),
            fileExists: { $0 == "Packages/Core/Package.swift" },
            fileContents: { _ in "// swift-tools-version:5.9" },
            entryNames: { ["Packages", "Apps"] }
        )
        XCTAssertEqual(fp, .swiftAppleApp)
    }

    // MARK: - Helpers

    private func tempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ARA-S04-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
