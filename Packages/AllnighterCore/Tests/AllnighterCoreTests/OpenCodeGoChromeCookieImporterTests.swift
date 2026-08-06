import CCommonCrypto
import XCTest
@testable import AllnighterCore

private func aes128cbcEncrypt(plaintext: Data, key: Data, iv: Data) -> Data {
    precondition(key.count == 16)
    precondition(iv.count == 16)
    var buf = [UInt8](repeating: 0, count: plaintext.count + 16)
    let bufCapacity = buf.count
    var moved = 0
    let status = plaintext.withUnsafeBytes { pt in
        key.withUnsafeBytes { k in
            iv.withUnsafeBytes { ivBytes in
                buf.withUnsafeMutableBytes { out in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(0),
                        k.baseAddress,
                        key.count,
                        ivBytes.baseAddress,
                        pt.baseAddress,
                        plaintext.count,
                        out.baseAddress,
                        bufCapacity,
                        &moved
                    )
                }
            }
        }
    }
    guard status == kCCSuccess, moved > 0 else { fatalError("test encrypt failed") }
    buf.removeLast(buf.count - moved)
    return Data(buf)
}

// MARK: - Helpers

private extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: chars.count / 2)
        var idx = 0
        while idx < chars.count {
            guard let h = Self.hexByteValue(chars[idx]),
                  let l = Self.hexByteValue(chars[idx + 1]) else { return nil }
            data.append((h << 4) | l)
            idx += 2
        }
        self = data
    }

    private static func hexByteValue(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x30...0x39: return b - 0x30
        case 0x41...0x46: return b - 0x41 + 10
        case 0x61...0x66: return b - 0x61 + 10
        default: return nil
        }
    }
}

final class OpenCodeGoChromeCookieImporterTests: XCTestCase {

    private let prefix32 = Data(repeating: 0xAB, count: 32)

    // MARK: - PBKDF2 known-vector test

    func testDeriveKeyKnownVector() {
        let knownKeyHex = "d9a09d499b4e1b7461f28e67972c6dbd"
        let key = OpenCodeGoChromeCookieImporter.deriveKey(password: "peanuts")
        XCTAssertEqual(key, Data(hex: knownKeyHex)!, "PBKDF2 output must match known vector")
    }

    // MARK: - AES-128-CBC decrypt (round-trip)

    func testDecryptRoundTrip() {
        let cookie = "test-cookie-value-12345"
        let plaintext = Data(cookie.utf8)
        var padded = prefix32 + plaintext
        let padLen = 16 - (padded.count % 16)
        padded.append(Data(repeating: UInt8(padLen), count: padLen))

        let key = Data(hex: "91913b9a70a198b5e0d5b47bf2c8a3e8")!
        let iv = Data(repeating: 0x20, count: 16)
        let ciphertext = aes128cbcEncrypt(plaintext: padded, key: key, iv: iv)
        let encrypted = Data("v10".utf8) + ciphertext

        let result = try! OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        XCTAssertEqual(result, cookie)
    }

    func testDecryptPrefix32BytesStripped() {
        let cookie = "longer-cookie-that-survives-prefix-removal"
        let plaintext = Data(cookie.utf8)
        var padded = prefix32 + plaintext
        let padLen = 16 - (padded.count % 16)
        padded.append(Data(repeating: UInt8(padLen), count: padLen))

        let key = Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let iv = Data(repeating: 0x20, count: 16)
        let ciphertext = aes128cbcEncrypt(plaintext: padded, key: key, iv: iv)
        let encrypted = Data("v10".utf8) + ciphertext

        let result = try! OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        XCTAssertEqual(result, cookie)
        XCTAssertFalse(result.hasPrefix("prefix"), "32-byte domain hash prefix must be stripped")
    }

    func testDecryptPaddingIsStrippedWithoutCorruption() {
        let cookie = "exact-block-cookie"
        let plaintext = Data(cookie.utf8)
        var padded = prefix32 + plaintext
        let padLen = 16 - (padded.count % 16)
        padded.append(Data(repeating: UInt8(padLen), count: padLen))
        XCTAssertEqual(padded.count % 16, 0)

        let key = Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let iv = Data(repeating: 0x20, count: 16)
        let ciphertext = aes128cbcEncrypt(plaintext: padded, key: key, iv: iv)
        let encrypted = Data("v10".utf8) + ciphertext

        let result = try! OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        XCTAssertEqual(result, cookie)
    }

    func testDecryptShortDataKeepsContent() {
        let cookie = "hi"
        var plaintext = Data(cookie.utf8)
        let padLen = 16 - (plaintext.count % 16)
        plaintext.append(Data(repeating: UInt8(padLen), count: padLen))

        let key = Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let iv = Data(repeating: 0x20, count: 16)
        let ciphertext = aes128cbcEncrypt(plaintext: plaintext, key: key, iv: iv)
        let encrypted = Data("v10".utf8) + ciphertext

        let result = try! OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        XCTAssertEqual(result, "hi")
    }

    func testDecryptV11PrefixAccepted() {
        let cookie = "v11-test-cookie"
        let plaintext = Data(cookie.utf8)
        var padded = prefix32 + plaintext
        let padLen = 16 - (padded.count % 16)
        padded.append(Data(repeating: UInt8(padLen), count: padLen))

        let key = Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let iv = Data(repeating: 0x20, count: 16)
        let ciphertext = aes128cbcEncrypt(plaintext: padded, key: key, iv: iv)
        let encrypted = Data("v11".utf8) + ciphertext

        let result = try! OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
        XCTAssertEqual(result, cookie)
    }

    // MARK: - Unexpected prefix

    func testUnexpectedPrefixFailsLoudly() {
        let encrypted = Data("v20".utf8) + Data(repeating: 0, count: 32)
        let key = Data(repeating: 0, count: 16)
        let result = Result { try OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? OpenCodeGoChromeCookieImporter.ImportError, .unexpectedPrefix("v20"))
    }

    func testEmptyCookieAfterDecryptFails() {
        let key = Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let iv = Data(repeating: 0x20, count: 16)
        let padLen: UInt8 = 15
        var padded = prefix32 + Data([0x20])
        padded.append(Data(repeating: padLen, count: 15))
        let ciphertext = aes128cbcEncrypt(plaintext: padded, key: key, iv: iv)
        let encrypted = Data("v10".utf8) + ciphertext

        let result = Result { try OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? OpenCodeGoChromeCookieImporter.ImportError, .emptyCookie)
    }

    // MARK: - Profile selection

    func testFindCookieSelectsCorrectProfile() throws {
        let fm = FileManager.default
        let chromeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-chrome-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: chromeRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: chromeRoot) }

        let defaultProfile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        let otherProfile = chromeRoot.appendingPathComponent("Profile 1", isDirectory: true)
        try fm.createDirectory(at: defaultProfile, withIntermediateDirectories: true)
        try fm.createDirectory(at: otherProfile, withIntermediateDirectories: true)

        let authHex = "763130" + Data(repeating: 0, count: 32).hex
        createCookiesDB(at: defaultProfile.appendingPathComponent("Cookies"),
                        hostKey: "opencode.ai", name: "auth", encryptedHex: authHex)
        createCookiesDB(at: otherProfile.appendingPathComponent("Cookies"),
                        hostKey: "opencode.ai", name: "auth", encryptedHex: authHex)

        let (profile, _) = try OpenCodeGoChromeCookieImporter.findCookie(
            chromeRoot: chromeRoot, fileManager: fm
        )
        XCTAssertEqual(profile, "Default", "must find the alphabetically first profile with the cookie")
    }

    func testFindCookieSkipsProfilesWithoutCookiesFile() throws {
        let fm = FileManager.default
        let chromeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-skip-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: chromeRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: chromeRoot) }

        let skipProfile = chromeRoot.appendingPathComponent("Profile 1", isDirectory: true)
        let hasProfile = chromeRoot.appendingPathComponent("Profile 2", isDirectory: true)
        try fm.createDirectory(at: skipProfile, withIntermediateDirectories: true)
        try fm.createDirectory(at: hasProfile, withIntermediateDirectories: true)

        let authHex = "763130" + Data(repeating: 0, count: 32).hex
        createCookiesDB(at: hasProfile.appendingPathComponent("Cookies"),
                        hostKey: "opencode.ai", name: "auth", encryptedHex: authHex)

        let (profile, _) = try OpenCodeGoChromeCookieImporter.findCookie(
            chromeRoot: chromeRoot, fileManager: fm
        )
        XCTAssertEqual(profile, "Profile 2")
    }

    func testChromeNotFound() {
        let fm = FileManager.default
        let noChrome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-no-chrome-\(UUID().uuidString)", isDirectory: true)
        let result = Result {
            try OpenCodeGoChromeCookieImporter.findCookie(chromeRoot: noChrome, fileManager: fm)
        }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? OpenCodeGoChromeCookieImporter.ImportError, .chromeNotFound)
    }

    func testCookieNotFoundWhenNoAuthCookie() throws {
        let fm = FileManager.default
        let chromeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-no-cookie-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: chromeRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: chromeRoot) }

        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        createCookiesDB(at: profile.appendingPathComponent("Cookies"),
                        hostKey: "other.example.com", name: "session",
                        encryptedHex: "763130".appending(Data(repeating: 0, count: 32).hex))

        let result = Result {
            try OpenCodeGoChromeCookieImporter.findCookie(chromeRoot: chromeRoot, fileManager: fm)
        }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? OpenCodeGoChromeCookieImporter.ImportError, .cookieNotFound)
    }

    // MARK: - Disclosure message content

    func testDisclosureNamesWhatIsAccessed() {
        let msg = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: "Profile 7")
        XCTAssertTrue(msg.contains("Chrome Safe Storage"), "must name what is accessed")
    }

    func testDisclosureExplainsWhyUnavoidable() {
        let msg = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: "Default")
        XCTAssertTrue(msg.contains("Chrome encrypts") || msg.contains("impossible without it"),
                      "must explain why keychain access is unavoidable")
    }

    func testDisclosureNamesWhereSecretEndsUp() {
        let msg = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: "Default")
        XCTAssertTrue(msg.contains("AES-GCM encrypted"), "must name where secret is stored")
        XCTAssertTrue(msg.contains("never printed"), "must state cookie is never printed")
        XCTAssertTrue(msg.contains("never written"), "must state cookie is never written to a file")
    }

    func testDisclosureNamesManualFallback() {
        let msg = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: "Default")
        XCTAssertTrue(msg.contains("pbpaste"), "must name the manual fallback command")
    }

    func testDisclosureIncludesProfileName() {
        let msg = OpenCodeGoChromeCookieImporter.disclosureMessage(profileName: "My Profile")
        XCTAssertTrue(msg.contains("My Profile"), "must name the profile where cookie was found")
    }

    // MARK: - Disclosure-before-keychain ordering

    func testDisclosureEmittedBeforeKeychainAccess() {
        let fm = FileManager.default
        let chromeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-order-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: chromeRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: chromeRoot) }

        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        try! fm.createDirectory(at: profile, withIntermediateDirectories: true)

        let authHex = "763130" + Data(repeating: 0, count: 32).hex
        createCookiesDB(at: profile.appendingPathComponent("Cookies"),
                        hostKey: "opencode.ai", name: "auth", encryptedHex: authHex)

        var disclosureReceived = false
        var keychainCalled = false

        _ = try? OpenCodeGoChromeCookieImporter.importWithDisclosure(
            chromeRoot: chromeRoot,
            fileManager: fm,
            keychainPassword: {
                keychainCalled = true
                return "not-real"
            },
            onDisclosure: { _ in
                disclosureReceived = true
                XCTAssertFalse(keychainCalled, "keychain must not be called before disclosure is emitted")
            }
        )

        XCTAssertTrue(disclosureReceived, "disclosure must be emitted")
        XCTAssertTrue(keychainCalled, "keychain must be attempted after disclosure")
    }

    func testKeychainDeniedReturnsCleanError() {
        let fm = FileManager.default
        let chromeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ocg-deny-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: chromeRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: chromeRoot) }

        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)
        try! fm.createDirectory(at: profile, withIntermediateDirectories: true)

        let authHex = "763130" + Data(repeating: 0, count: 32).hex
        createCookiesDB(at: profile.appendingPathComponent("Cookies"),
                        hostKey: "opencode.ai", name: "auth", encryptedHex: authHex)

        let result = Result(catching: {
            try OpenCodeGoChromeCookieImporter.importWithDisclosure(
                chromeRoot: chromeRoot,
                fileManager: fm,
                keychainPassword: { throw OpenCodeGoChromeCookieImporter.ImportError.keychainDenied },
                onDisclosure: { _ in }
            )
        })

        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? OpenCodeGoChromeCookieImporter.ImportError, .keychainDenied)
    }

    // MARK: - Helpers

    private func createCookiesDB(at url: URL, hostKey: String, name: String, encryptedHex: String) {
        let sql = #"""
        CREATE TABLE IF NOT EXISTS cookies (
            host_key TEXT, name TEXT, encrypted_value BLOB
        );
        INSERT INTO cookies (host_key, name, encrypted_value)
        VALUES ('\#(hostKey)', '\#(name)', x'\#(encryptedHex)');
        """#
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [url.path, sql]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try! proc.run()
        proc.waitUntilExit()
    }
}
