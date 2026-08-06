import CCommonCrypto
import Foundation

/// Chrome cookie import for Bailian Token Plan Personal (intl).
///
/// Reads every Alibaba Cloud session cookie from Chrome, then builds a
/// host-scoped `Cookie` header for `bailian-singapore-cs.alibabacloud.com`.
/// Do not paste a single cookie from Application — the quota API needs the
/// full scoped header (dozens of name=value pairs).
public enum BailianTokenPlanChromeCookieImporter {

    public enum ImportError: Error, Equatable {
        case chromeNotFound
        case cookieNotFound
        case notAuthenticated
        case keychainDenied
        case decryptionFailed
        case emptyCookieHeader
    }

    public static let defaultChromeRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)

    public static let quotaURL = URL(string:
        "https://bailian-singapore-cs.alibabacloud.com/data/api.json"
        + "?action=IntlBroadScopeAspnGateway"
        + "&product=sfm_bailian"
        + "&api=zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
        + "&_v=undefined"
    )!

    private static let domainPatterns = ["alibabacloud.com", "aliyun.com"]

    struct CookieRecord: Sendable, Equatable {
        let domain: String
        let name: String
        let path: String
        let value: String
    }

    // MARK: - Disclosure

    public static func disclosureMessage(profileName: String, cookieCount: Int) -> String {
        """
        Found \(cookieCount) Alibaba Cloud session cookies in Chrome profile: \(profileName)

        macOS is about to ask for your login keychain password.

          WHAT   Chrome's "Chrome Safe Storage" key — nothing else.
          WHY    Chrome encrypts every cookie VALUE with that key. Reading your own
                 cookies is impossible without it; this is Chrome's design, not ours.
          WHERE  The cookies are decrypted in memory, scoped to the Token Plan quota
                 host, then stored AES-GCM encrypted at rest. They are never printed,
                 never written to a file, never passed as a command argument, and never
                 enter shell history.
          ONCE   Choose "Always Allow" and macOS stops asking.

          DECLINE  Press Deny and nothing is read. Manual fallback:
                     DevTools → Network → usage request → copy the full Cookie header
                     pbpaste | alln bailian-token-plan configure
        """
    }

    // MARK: - Import

    public static func importWithDisclosure(
        chromeRoot: URL = defaultChromeRoot,
        fileManager: FileManager = .default,
        keychainPassword: () throws -> String = OpenCodeGoChromeCookieImporter.readKeychainPassword,
        onDisclosure: (String) -> Void
    ) throws -> (cookieHeader: String, profileName: String) {
        let (profileName, rows) = try findEncryptedRows(chromeRoot: chromeRoot, fileManager: fileManager)
        onDisclosure(disclosureMessage(profileName: profileName, cookieCount: rows.count))
        let header = try cookieHeaderFromRows(rows, keychainPassword: keychainPassword)
        return (header, profileName)
    }

    /// Decrypts rows found by `findEncryptedRows` after disclosure.
    static func importAfterDisclosure(
        rows: [CookieRow],
        profileName: String,
        keychainPassword: () throws -> String = OpenCodeGoChromeCookieImporter.readKeychainPassword
    ) throws -> (cookieHeader: String, profileName: String) {
        let header = try cookieHeaderFromRows(rows, keychainPassword: keychainPassword)
        return (header, profileName)
    }

    /// Reads cookie rows from Chrome without touching the keychain (for disclosure-first CLI).
    static func findEncryptedRows(
        chromeRoot: URL = defaultChromeRoot,
        fileManager: FileManager = .default
    ) throws -> (profileName: String, rows: [CookieRow]) {
        guard fileManager.fileExists(atPath: chromeRoot.path) else {
            throw ImportError.chromeNotFound
        }
        let profileDirs = try fileManager.contentsOfDirectory(
            at: chromeRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        for profileDir in profileDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let cookiesDB = profileDir.appendingPathComponent("Cookies")
            guard fileManager.fileExists(atPath: cookiesDB.path) else { continue }

            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("alln-bailian-cookies-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            let tempDB = tempDir.appendingPathComponent("Cookies")
            try fileManager.copyItem(at: cookiesDB, to: tempDB)
            let rows = try readCookieRows(from: tempDB.path)
            guard !rows.isEmpty else { continue }
            return (profileDir.lastPathComponent, rows)
        }
        throw ImportError.cookieNotFound
    }

    static func decryptRecords(
        _ rows: [CookieRow],
        keychainPassword: () throws -> String = OpenCodeGoChromeCookieImporter.readKeychainPassword
    ) throws -> [CookieRecord] {
        let password = try keychainPassword()
        let key = OpenCodeGoChromeCookieImporter.deriveKey(password: password)
        return rows.compactMap { row in
            guard let value = decryptValue(row: row, key: key) else { return nil }
            return CookieRecord(
                domain: normalizeDomain(row.domain),
                name: row.name,
                path: row.path.isEmpty ? "/" : row.path,
                value: value
            )
        }
    }

    static func cookieHeaderFromRows(
        _ rows: [CookieRow],
        keychainPassword: () throws -> String = OpenCodeGoChromeCookieImporter.readKeychainPassword
    ) throws -> String {
        let records = try decryptRecords(rows, keychainPassword: keychainPassword)
        guard let header = cookieHeader(for: records, targetURL: quotaURL), !header.isEmpty else {
            throw ImportError.emptyCookieHeader
        }
        guard looksAuthenticated(cookieHeader: header) else {
            throw ImportError.notAuthenticated
        }
        return header
    }

    // MARK: - Cookie discovery

    static func findCookies(
        chromeRoot: URL,
        fileManager: FileManager,
        keychainPassword: (() throws -> String)? = nil
    ) throws -> (profileName: String, records: [CookieRecord]) {
        let (profileName, rows) = try findEncryptedRows(chromeRoot: chromeRoot, fileManager: fileManager)
        let decrypt: () throws -> String = {
            if let keychainPassword { return try keychainPassword() }
            return try OpenCodeGoChromeCookieImporter.readKeychainPassword()
        }
        let records = try decryptRecords(rows, keychainPassword: decrypt)
        guard !records.isEmpty else { throw ImportError.cookieNotFound }
        return (profileName, records)
    }

    struct CookieRow: Sendable, Equatable {
        let domain: String
        let name: String
        let path: String
        let plainValue: String?
        let encryptedHex: String?
    }

    private static func readCookieRows(from dbPath: String) throws -> [CookieRow] {
        let domainClause = domainPatterns
            .map { "host_key like '%\($0)%'" }
            .joined(separator: " or ")
        let query = """
            select host_key, name, path, hex(encrypted_value), value
            from cookies
            where \(domainClause)
            """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-readonly", dbPath, query]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [] }

        let output = String(data: try outPipe.fileHandleForReading.readToEnd() ?? Data(), encoding: .utf8) ?? ""
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            let domain = String(parts[0])
            let name = String(parts[1])
            let path = String(parts[2])
            let encryptedHex = parts.count > 3 ? String(parts[3]) : ""
            let plain = parts.count > 4 ? String(parts[4]) : ""
            return CookieRow(
                domain: domain,
                name: name,
                path: path,
                plainValue: plain.isEmpty ? nil : plain,
                encryptedHex: encryptedHex.isEmpty ? nil : encryptedHex
            )
        }
    }

    private static func decryptValue(row: CookieRow, key: Data) -> String? {
        if let plain = row.plainValue, !plain.isEmpty {
            return plain
        }
        guard let hex = row.encryptedHex, let encrypted = hexToData(hex) else { return nil }
        return try? OpenCodeGoChromeCookieImporter.decrypt(encrypted: encrypted, key: key)
    }

    // MARK: - Header builder

    static func cookieHeader(for records: [CookieRecord], targetURL: URL) -> String? {
        var byName: [String: CookieRecord] = [:]
        for record in records {
            guard matchesRequestURL(record: record, url: targetURL) else { continue }
            if let existing = byName[record.name] {
                if sortKey(record) >= sortKey(existing) {
                    byName[record.name] = record
                }
            } else {
                byName[record.name] = record
            }
        }
        guard !byName.isEmpty else { return nil }
        return byName.keys.sorted().compactMap { name in
            guard let record = byName[name] else { return nil }
            return "\(record.name)=\(record.value)"
        }.joined(separator: "; ")
    }

    static func looksAuthenticated(cookieHeader: String) -> Bool {
        let names = cookieHeader
            .split(separator: ";")
            .compactMap { pair -> String? in
                let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let eq = trimmed.firstIndex(of: "=") else { return nil }
                return String(trimmed[..<eq])
            }
        let authNames: Set<String> = [
            "login_aliyunid",
            "login_aliyunid_csrf",
            "aliyunid",
            "_hvn_login",
        ]
        return names.contains(where: { authNames.contains($0) })
    }

    static func matchesRequestURL(record: CookieRecord, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = record.domain.lowercased()
        guard host == domain || host.hasSuffix(".\(domain)") else { return false }

        let cookiePath = record.path.isEmpty ? "/" : record.path
        let requestPath = url.path.isEmpty ? "/" : url.path
        if requestPath == cookiePath { return true }
        guard requestPath.hasPrefix(cookiePath) else { return false }
        if cookiePath == "/" || cookiePath.hasSuffix("/") { return true }
        guard let boundary = requestPath.index(
            requestPath.startIndex,
            offsetBy: cookiePath.count,
            limitedBy: requestPath.endIndex
        ), boundary < requestPath.endIndex else {
            return true
        }
        return requestPath[boundary] == "/"
    }

    private static func sortKey(_ record: CookieRecord) -> (Int, Int) {
        (record.path.count, record.domain.count)
    }

    private static func normalizeDomain(_ domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func hexToData(_ hex: String) -> Data? {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: chars.count / 2)
        var idx = 0
        while idx < chars.count {
            guard let h = hexByteValue(chars[idx]), let l = hexByteValue(chars[idx + 1]) else { return nil }
            data.append((h << 4) | l)
            idx += 2
        }
        return data
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
