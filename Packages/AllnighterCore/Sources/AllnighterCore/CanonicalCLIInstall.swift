import Foundation

public enum CanonicalCLIInstall {

    public static let binaryName = "alln"

    public struct CodeIdentity: Codable, Equatable, Sendable {
        public var cdhash: String?
        public var version: String?

        public init(cdhash: String?, version: String?) {
            self.cdhash = cdhash
            self.version = version
        }
    }

    public struct Report: Equatable, Sendable {
        public let canonicalURL: URL
        public let alreadyCanonical: Bool
        public let rollbackURL: URL?

        public init(canonicalURL: URL, alreadyCanonical: Bool, rollbackURL: URL?) {
            self.canonicalURL = canonicalURL
            self.alreadyCanonical = alreadyCanonical
            self.rollbackURL = rollbackURL
        }
    }

    public struct Failure: Error, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    // MARK: - Paths

    public static func canonicalDirectory(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(".local/share/allnighter/bin", isDirectory: true)
    }

    public static func canonicalBinaryURL(homeDirectory: URL) -> URL {
        canonicalDirectory(homeDirectory: homeDirectory).appendingPathComponent(binaryName)
    }

    public static func rollbackBinaryURL(homeDirectory: URL) -> URL {
        let canonical = canonicalBinaryURL(homeDirectory: homeDirectory)
        return canonical.deletingLastPathComponent().appendingPathComponent("\(binaryName).rollback")
    }

    public static func pathSymlinkURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(".local/bin/\(binaryName)")
    }

    public static func rollbackRecoveryCopyCommand(canonicalURL: URL, rollbackURL: URL) -> String {
        "cp \"\(rollbackURL.path)\" \"\(canonicalURL.path)\""
    }

    public static func identityRecordURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Allnighter", isDirectory: true)
            .appendingPathComponent("installed-binary.json")
    }

    // MARK: - Candidate refusal

    public static func refusalReason(forCandidate candidateURL: URL, homeDirectory: URL) -> String? {
        let path = candidateURL.path
        for component in candidateURL.pathComponents {
            if component.hasSuffix(".app") {
                return "candidate is inside an .app bundle: \(path)"
            }
        }
        let resolvedHome = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        for dir in ["Downloads", "Desktop", "Documents"] {
            let dirPath = resolvedHome.appendingPathComponent(dir).path
            let resolved = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved.hasPrefix(dirPath + "/") || resolved == dirPath {
                return "candidate is under ~/\(dir): \(path)"
            }
        }
        return nil
    }

    // MARK: - Identity

    private struct IdentityRecord: Codable {
        let schemaVersion: Int
        let canonicalPath: String
        let identity: CodeIdentity
        let updatedAt: Date
    }

    public static func computeCDHash(
        candidateURL: URL,
        processRunner: (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32)
    ) -> String? {
        let result = processRunner("/usr/bin/codesign", ["-dvvv", candidateURL.path])
        guard result.exitCode == 0 else { return nil }
        for line in result.stderr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CDHash=") {
                return String(trimmed.dropFirst("CDHash=".count))
            }
        }
        return nil
    }

    // MARK: - Install

    public static func install(
        candidateURL: URL,
        homeDirectory: URL,
        version: String? = nil,
        fileManager: FileManager = .default,
        processRunner: @escaping (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32) = { _, _ in
            (stdout: "", stderr: "process runner not configured", exitCode: -1)
        },
        beforeBytesChange: @escaping () -> Result<Void, Failure> = { .success(()) }
    ) -> Result<Report, Failure> {
        if let reason = refusalReason(forCandidate: candidateURL, homeDirectory: homeDirectory) {
            return .failure(Failure(code: "INSTALL_CANDIDATE_REFUSED", message: reason))
        }

        let canonicalURL = canonicalBinaryURL(homeDirectory: homeDirectory)
        let resolvedCanonical = canonicalURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
        if resolvedCandidate == resolvedCanonical {
            return .success(Report(canonicalURL: canonicalURL, alreadyCanonical: true, rollbackURL: nil))
        }

        let canonicalDir = canonicalDirectory(homeDirectory: homeDirectory)
        do {
            try fileManager.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        } catch {
            return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                   message: "could not create canonical directory \(canonicalDir.path): \(error.localizedDescription)"))
        }

        guard let candidateData = try? Data(contentsOf: candidateURL), !candidateData.isEmpty else {
            return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                   message: "could not read candidate bytes from \(candidateURL.path)"))
        }

        let tempURL = canonicalDir.appendingPathComponent(".\(binaryName).staging.\(UUID().uuidString)")
        do {
            try candidateData.write(to: tempURL, options: .atomic)
        } catch {
            return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                   message: "could not write temp binary to \(tempURL.path): \(error.localizedDescription)"))
        }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                   message: "could not set executable bit on \(tempURL.path): \(error.localizedDescription)"))
        }

        let rollbackURL = rollbackBinaryURL(homeDirectory: homeDirectory)
        let canonicalExists = fileManager.fileExists(atPath: canonicalURL.path)
        if canonicalExists {
            if fileManager.fileExists(atPath: rollbackURL.path) {
                try? fileManager.removeItem(at: rollbackURL)
            }
            do {
                try fileManager.moveItem(at: canonicalURL, to: rollbackURL)
            } catch {
                try? fileManager.removeItem(at: tempURL)
                return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                       message: "could not move existing canonical binary to rollback \(rollbackURL.path): \(error.localizedDescription)"))
            }
        }

        switch beforeBytesChange() {
        case .success:
            break
        case .failure(let failure):
            if canonicalExists {
                _ = try? fileManager.moveItem(at: rollbackURL, to: canonicalURL)
            }
            try? fileManager.removeItem(at: tempURL)
            return .failure(failure)
        }

        do {
            try fileManager.moveItem(at: tempURL, to: canonicalURL)
        } catch {
            if canonicalExists {
                let restoreResult = Result { try fileManager.moveItem(at: rollbackURL, to: canonicalURL) }
                switch restoreResult {
                case .success:
                    return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                           message: "rename to \(canonicalURL.path) failed: \(error.localizedDescription); prior bytes restored"))
                case .failure(let restoreError):
                    return .failure(Failure(code: "SERVE_ROLLBACK_FAILED",
                                           message: "rename to \(canonicalURL.path) failed: \(error.localizedDescription); rollback restore also failed at \(rollbackURL.path): \(restoreError.localizedDescription)"))
                }
            }
            try? fileManager.removeItem(at: tempURL)
            return .failure(Failure(code: "SERVE_INSTALL_FAILED",
                                   message: "rename to \(canonicalURL.path) failed: \(error.localizedDescription)"))
        }

        do {
            try CLIResourceBundles.copySiblings(
                from: candidateURL,
                into: canonicalDir,
                fileManager: fileManager
            )
        } catch {
            return .failure(Failure(
                code: "SERVE_INSTALL_FAILED",
                message: "could not copy CLI resource bundles into \(canonicalDir.path): \(error.localizedDescription)"
            ))
        }

        let cdhash = computeCDHash(candidateURL: candidateURL, processRunner: processRunner)
        let identity = CodeIdentity(cdhash: cdhash, version: version)
        let record = IdentityRecord(schemaVersion: 1, canonicalPath: canonicalURL.path, identity: identity, updatedAt: Date())
        let identityURL = identityRecordURL(homeDirectory: homeDirectory)
        do {
            let identityDir = identityURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: identityDir, withIntermediateDirectories: true)
            try CoreJSON.encode(record).write(to: identityURL, options: .atomic)
        } catch {
            // identity write is non-fatal
        }

        let reportRollback: URL? = canonicalExists ? rollbackURL : nil
        return .success(Report(canonicalURL: canonicalURL, alreadyCanonical: false, rollbackURL: reportRollback))
    }

    // MARK: - Failed install restore (ASR-S06e)

    /// Single owner for §4.3 step 7 rollback: restore binary from `<canonical>.rollback`,
    /// verify the PATH symlink, and restore prior plist bytes. Callers must bootstrap the
    /// prior job only after this returns `.success`.
    public static func restorePriorInstallState(
        homeDirectory: URL,
        plistURL: URL,
        priorPlistBytes: Data?,
        canonicalURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Result<Void, Failure> {
        let canonicalURL = canonicalURL ?? canonicalBinaryURL(homeDirectory: homeDirectory)
        let rollbackURL = canonicalURL.deletingLastPathComponent().appendingPathComponent("\(binaryName).rollback")
        let symlinkURL = pathSymlinkURL(homeDirectory: homeDirectory)

        if fileManager.fileExists(atPath: rollbackURL.path) {
            if fileManager.fileExists(atPath: canonicalURL.path) {
                do {
                    try fileManager.removeItem(at: canonicalURL)
                } catch {
                    return .failure(Failure(
                        code: "SERVE_ROLLBACK_FAILED",
                        message: "could not remove candidate binary at \(canonicalURL.path): \(error.localizedDescription); recover with: \(rollbackRecoveryCopyCommand(canonicalURL: canonicalURL, rollbackURL: rollbackURL))"
                    ))
                }
            }
            do {
                try fileManager.moveItem(at: rollbackURL, to: canonicalURL)
            } catch {
                return .failure(Failure(
                    code: "SERVE_ROLLBACK_FAILED",
                    message: "could not restore prior binary from \(rollbackURL.path) to \(canonicalURL.path): \(error.localizedDescription); recover with: \(rollbackRecoveryCopyCommand(canonicalURL: canonicalURL, rollbackURL: rollbackURL))"
                ))
            }
        }

        let canonicalResolved = canonicalURL.resolvingSymlinksInPath().standardizedFileURL.path
        if fileManager.fileExists(atPath: symlinkURL.path) {
            let symlinkResolved = symlinkURL.resolvingSymlinksInPath().standardizedFileURL.path
            if symlinkResolved != canonicalResolved {
                do {
                    try fileManager.removeItem(at: symlinkURL)
                    try fileManager.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: canonicalResolved)
                } catch {
                    return .failure(Failure(
                        code: "SERVE_INSTALL_FAILED",
                        message: "could not repair PATH symlink at \(symlinkURL.path): \(error.localizedDescription)"
                    ))
                }
            }
        }

        if let priorBytes = priorPlistBytes {
            do {
                try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try priorBytes.write(to: plistURL, options: .atomic)
            } catch {
                return .failure(Failure(
                    code: "SERVE_INSTALL_FAILED",
                    message: "could not restore prior plist at \(plistURL.path): \(error.localizedDescription)"
                ))
            }
        }

        return .success(())
    }
}
