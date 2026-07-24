import Foundation

/// Intentionally tiny launchd helper for the resident-project TCC investigation.
/// It has no Allnighter imports, no vendor CLI knowledge, and no product stores.
/// Its only meaningful operation is changing to one supplied directory and
/// enumerating it once, then writing a JSON receipt outside protected folders.
@main
struct TCCProjectAccessHarness {
    struct Receipt: Codable {
        var schemaVersion = 1
        var timestamp: Date
        var pid: Int32
        var mode: String
        var requestedDirectory: String
        var effectiveDirectory: String
        var touchedEntryCount: Int?
        var error: String?
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else {
            FileHandle.standardError.write(Data(
                "usage: tcc-project-access-helper <mode> <directory> <receipt-path>\\n".utf8
            ))
            return
        }

        let mode = arguments[0]
        let directory = arguments[1]
        let receiptURL = URL(fileURLWithPath: arguments[2])
        let fileManager = FileManager.default
        var receipt = Receipt(
            timestamp: Date(),
            pid: ProcessInfo.processInfo.processIdentifier,
            mode: mode,
            requestedDirectory: directory,
            effectiveDirectory: fileManager.currentDirectoryPath,
            touchedEntryCount: nil,
            error: nil
        )

        do {
            guard fileManager.changeCurrentDirectoryPath(directory) else {
                throw CocoaError(.fileNoSuchFile)
            }
            receipt.effectiveDirectory = fileManager.currentDirectoryPath
            // This is the only target-directory read. Directory enumeration is
            // sufficient to exercise the protected-folder primitive without
            // opening a source file or launching a vendor process.
            receipt.touchedEntryCount = try fileManager.contentsOfDirectory(atPath: ".").count
        } catch {
            receipt.error = String(describing: error)
        }

        do {
            try fileManager.createDirectory(
                at: receiptURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(receipt)
            try data.write(to: receiptURL, options: .atomic)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("could not write receipt: \(error)\\n".utf8))
        }
    }
}
