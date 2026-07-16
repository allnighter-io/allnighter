import Foundation

/// Doctor check: is `alln` on PATH and pointing at this binary?
/// Injectable PATH/filesystem seam — unit tests never read the real PATH.
public enum BinaryOnPath {
    public static let checkName = "binary.onPath"

    public static func check(
        runningBinary: String?,
        pathEnvironment: String?,
        fileManager: FileManager = .default
    ) -> DoctorResult.Check {
        guard let runningBinary else {
            return .init(
                name: checkName,
                status: .notChecked,
                detail: "running binary path not available"
            )
        }
        guard pathEnvironment != nil else {
            return .init(
                name: checkName,
                status: .notChecked,
                detail: "PATH not available to resolve `alln`"
            )
        }

        if InstallCLI.onPath(runningBinary: runningBinary, pathEnvironment: pathEnvironment, fileManager: fileManager) {
            return .init(
                name: checkName,
                status: .ok,
                detail: "`alln` on PATH resolves to this binary"
            )
        }

        return .init(
            name: checkName,
            status: .degraded,
            detail: "`alln` is not on PATH or points at a different binary",
            fixCommand: "alln install-cli"
        )
    }
}
