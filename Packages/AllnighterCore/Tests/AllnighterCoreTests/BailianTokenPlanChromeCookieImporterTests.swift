import XCTest
@testable import AllnighterCore

final class BailianTokenPlanChromeCookieImporterTests: XCTestCase {

    // MARK: - Cookie header builder

    func testCookieHeaderScopesToQuotaHost() {
        let records = [
            record(domain: "alibabacloud.com", name: "login_aliyunid", value: "abc", path: "/"),
            record(domain: "other.example.com", name: "noise", value: "x", path: "/"),
            record(domain: "bailian-singapore-cs.alibabacloud.com", name: "session", value: "tok", path: "/"),
        ]
        let header = BailianTokenPlanChromeCookieImporter.cookieHeader(
            for: records,
            targetURL: BailianTokenPlanChromeCookieImporter.quotaURL
        )
        XCTAssertEqual(header, "login_aliyunid=abc; session=tok")
        XCTAssertFalse(header?.contains("noise") ?? true)
    }

    func testLooksAuthenticatedRequiresLoginCookie() {
        XCTAssertTrue(BailianTokenPlanChromeCookieImporter.looksAuthenticated(
            cookieHeader: "login_aliyunid=abc; foo=bar"
        ))
        XCTAssertFalse(BailianTokenPlanChromeCookieImporter.looksAuthenticated(
            cookieHeader: "_ga=1; _gid=2"
        ))
    }

    // MARK: - Encrypted row discovery (no keychain)

    func testFindEncryptedRowsSelectsFirstProfileWithCookies() throws {
        let fm = FileManager.default
        let chromeRoot = tempChromeRoot()
        defer { try? fm.removeItem(at: chromeRoot) }

        let defaultProfile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        let otherProfile = chromeRoot.appendingPathComponent("Profile 1", isDirectory: true)
        try fm.createDirectory(at: defaultProfile, withIntermediateDirectories: true)
        try fm.createDirectory(at: otherProfile, withIntermediateDirectories: true)

        createCookiesDB(
            at: defaultProfile.appendingPathComponent("Cookies"),
            rows: [("modelstudio.console.alibabacloud.com", "login_aliyunid", "/", "session-abc")]
        )
        createCookiesDB(
            at: otherProfile.appendingPathComponent("Cookies"),
            rows: [("modelstudio.console.alibabacloud.com", "login_aliyunid", "/", "other")]
        )

        let (profile, rows) = try BailianTokenPlanChromeCookieImporter.findEncryptedRows(
            chromeRoot: chromeRoot,
            fileManager: fm
        )
        XCTAssertEqual(profile, "Default")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].plainValue, "session-abc")
    }

    func testFindEncryptedRowsSkipsNonAlibabaDomains() {
        let fm = FileManager.default
        let chromeRoot = tempChromeRoot()
        defer { try? fm.removeItem(at: chromeRoot) }

        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        try! fm.createDirectory(at: profile, withIntermediateDirectories: true)
        createCookiesDB(
            at: profile.appendingPathComponent("Cookies"),
            rows: [("opencode.ai", "auth", "/", "x")]
        )

        let result = Result {
            try BailianTokenPlanChromeCookieImporter.findEncryptedRows(
                chromeRoot: chromeRoot,
                fileManager: fm
            )
        }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? BailianTokenPlanChromeCookieImporter.ImportError, .cookieNotFound)
    }

    // MARK: - Disclosure ordering

    func testDisclosureEmittedBeforeKeychainAccess() throws {
        let fm = FileManager.default
        let chromeRoot = tempChromeRoot()
        defer { try? fm.removeItem(at: chromeRoot) }

        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        createCookiesDB(
            at: profile.appendingPathComponent("Cookies"),
            rows: [
                (".alibabacloud.com", "login_aliyunid", "/", "logged-in"),
                (".alibabacloud.com", "aliyunid", "/", "id"),
            ]
        )

        var disclosureReceived = false
        var keychainCalled = false

        _ = try? BailianTokenPlanChromeCookieImporter.importWithDisclosure(
            chromeRoot: chromeRoot,
            fileManager: fm,
            keychainPassword: {
                keychainCalled = true
                return "not-real"
            },
            onDisclosure: { _ in
                disclosureReceived = true
                XCTAssertFalse(keychainCalled, "keychain must not be called before disclosure")
            }
        )

        XCTAssertTrue(disclosureReceived)
        XCTAssertTrue(keychainCalled)
    }

    func testDisclosureIncludesCookieCount() {
        let msg = BailianTokenPlanChromeCookieImporter.disclosureMessage(
            profileName: "Profile 7",
            cookieCount: 42
        )
        XCTAssertTrue(msg.contains("42"))
        XCTAssertTrue(msg.contains("Profile 7"))
        XCTAssertTrue(msg.contains("Chrome Safe Storage"))
        XCTAssertTrue(msg.contains("pbpaste"))
    }

    // MARK: - Helpers

    private func tempChromeRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bailian-chrome-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(
        domain: String,
        name: String,
        value: String,
        path: String
    ) -> BailianTokenPlanChromeCookieImporter.CookieRecord {
        BailianTokenPlanChromeCookieImporter.CookieRecord(
            domain: domain,
            name: name,
            path: path,
            value: value
        )
    }

    private func createCookiesDB(
        at url: URL,
        rows: [(hostKey: String, name: String, path: String, plainValue: String)]
    ) {
        var sql = """
        CREATE TABLE IF NOT EXISTS cookies (
            host_key TEXT, name TEXT, path TEXT, encrypted_value BLOB, value TEXT
        );
        """
        for row in rows {
            sql += """
            INSERT INTO cookies (host_key, name, path, encrypted_value, value)
            VALUES ('\(row.hostKey)', '\(row.name)', '\(row.path)', x'', '\(row.plainValue)');
            """
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [url.path, sql]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try! proc.run()
        proc.waitUntilExit()
    }
}
