import CCommonCrypto
import Foundation

public enum OpenCodeGoChromeCookieImporter {

    public enum ImportError: Error, Equatable {
        case chromeNotFound
        case cookieNotFound
        case keychainDenied
        case unexpectedPrefix(String)
        case decryptionFailed
        case emptyCookie
    }

    public static let defaultChromeRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)

    // MARK: - Disclosure message

    public static func disclosureMessage(profileName: String) -> String {
        """
        Found the opencode.ai 'auth' cookie in Chrome profile: \(profileName)

        macOS is about to ask for your login keychain password.

          WHAT   Chrome's "Chrome Safe Storage" key — nothing else.
          WHY    Chrome encrypts every cookie VALUE with that key. Reading your own
                 cookie is impossible without it; this is Chrome's design, not ours.
          WHERE  The cookie is decrypted in memory and stored AES-GCM encrypted at
                 rest. It is never printed, never written to a file, never passed as a
                 command argument, and never enters shell history.
          ONCE   Choose "Always Allow" and macOS stops asking.

          DECLINE  Press Deny and nothing is read. You can still set it up by hand:
                     pbpaste | alln opencode-go configure
        """
    }

    // MARK: - Find cookie (no keychain access)

    public static func findCookie(
        chromeRoot: URL,
        fileManager: FileManager
    ) throws -> (profileName: String, encryptedValue: Data) {
        guard fileManager.fileExists(atPath: chromeRoot.path) else {
            throw ImportError.chromeNotFound
        }
        let profileDirs: [URL]
        do {
            profileDirs = try fileManager.contentsOfDirectory(
                at: chromeRoot,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw ImportError.chromeNotFound
        }

        for profileDir in profileDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let cookiesDB = profileDir.appendingPathComponent("Cookies")
            guard fileManager.fileExists(atPath: cookiesDB.path) else { continue }

            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("alln-chrome-cookies-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            let tempDB = tempDir.appendingPathComponent("Cookies")
            try fileManager.copyItem(at: cookiesDB, to: tempDB)

            let query = (
                "select hex(encrypted_value) from cookies "
                + "where host_key like '%opencode.ai%' and name='auth' "
                + "order by length(encrypted_value) desc limit 1"
            )
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            proc.arguments = ["-readonly", tempDB.path, query]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()

            guard proc.terminationStatus == 0 else { continue }
            let output = try (outPipe.fileHandleForReading.readToEnd() ?? Data())
            let hex = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !hex.isEmpty else { continue }

            guard let data = hexToData(hex) else { continue }
            return (profileDir.lastPathComponent, data)
        }
        throw ImportError.cookieNotFound
    }

    // MARK: - Key derivation (testable — pure PBKDF2)

    public static func deriveKey(password: String) -> Data {
        let passwordCStr = password.utf8CString
        let saltBytes: [UInt8] = Array("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: 16)

        _ = passwordCStr.withUnsafeBufferPointer { pwBuf in
            saltBytes.withUnsafeBufferPointer { saltBuf in
                derived.withUnsafeMutableBufferPointer { dkBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBuf.baseAddress,
                        passwordCStr.count - 1,
                        saltBuf.baseAddress,
                        saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        dkBuf.baseAddress,
                        16
                    )
                }
            }
        }
        return Data(derived)
    }

    // MARK: - Decrypt (testable — pure AES-128-CBC)

    public static func decrypt(encrypted: Data, key: Data) throws -> String {
        guard key.count == 16 else {
            throw ImportError.decryptionFailed
        }
        let prefixLength = 3
        guard encrypted.count > prefixLength else {
            throw ImportError.decryptionFailed
        }
        let prefix = String(decoding: encrypted.prefix(prefixLength), as: UTF8.self)
        guard prefix == "v10" || prefix == "v11" else {
            throw ImportError.unexpectedPrefix(prefix)
        }
        let ciphertext = encrypted.dropFirst(prefixLength)

        let iv: [UInt8] = Array(repeating: 0x20, count: 16)
        var buf = [UInt8](repeating: 0, count: ciphertext.count + 16)
        let bufCapacity = buf.count
        var dataOutMoved = 0

        let status = ciphertext.withUnsafeBytes { ct in
            key.withUnsafeBytes { k in
                iv.withUnsafeBufferPointer { ivBuf in
                    buf.withUnsafeMutableBytes { outBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(0),
                            k.baseAddress,
                            key.count,
                            ivBuf.baseAddress,
                            ct.baseAddress,
                            ciphertext.count,
                            outBuf.baseAddress,
                            bufCapacity,
                            &dataOutMoved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess, dataOutMoved > 0 else {
            throw ImportError.decryptionFailed
        }
        buf.removeLast(buf.count - dataOutMoved)

        let padLen = Int(buf.last ?? 0)
        guard padLen > 0, padLen <= 16, padLen <= buf.count,
              buf.suffix(padLen).allSatisfy({ $0 == padLen }) else {
            throw ImportError.decryptionFailed
        }
        buf.removeLast(padLen)

        if buf.count > 32 {
            buf.removeFirst(32)
        }

        let cookie = String(decoding: buf, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            throw ImportError.emptyCookie
        }
        return cookie
    }

    // MARK: - Keychain

    public static func readKeychainPassword() throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = [
            "find-generic-password", "-w",
            "-s", "Chrome Safe Storage",
            "-a", "Chrome"
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0, let data = try? outPipe.fileHandleForReading.readToEnd() else {
            throw ImportError.keychainDenied
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    // MARK: - Full import pipeline with disclosure-before-keychain ordering

    /// Finds the cookie, emits a disclosure via `onDisclosure`, then accesses
    /// the keychain. The `onDisclosure` closure is called BEFORE `keychainPassword`
    /// is invoked. In tests, this ordering is verified by recording which
    /// closure was called first.
    public static func importWithDisclosure(
        chromeRoot: URL = defaultChromeRoot,
        fileManager: FileManager = .default,
        keychainPassword: () throws -> String = readKeychainPassword,
        onDisclosure: (String) -> Void
    ) throws -> (cookie: String, profileName: String) {
        let (profileName, encrypted) = try findCookie(chromeRoot: chromeRoot, fileManager: fileManager)
        onDisclosure(disclosureMessage(profileName: profileName))
        let password = try keychainPassword()
        let key = deriveKey(password: password)
        let cookie = try decrypt(encrypted: encrypted, key: key)
        return (cookie, profileName)
    }

    // MARK: - Private helpers

    private static func hexToData(_ hex: String) -> Data? {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: chars.count / 2)
        var idx = 0
        while idx < chars.count {
            let h = hexByteValue(chars[idx])
            let l = hexByteValue(chars[idx + 1])
            guard let h, let l else { return nil }
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
