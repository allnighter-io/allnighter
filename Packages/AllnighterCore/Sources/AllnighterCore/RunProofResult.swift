import Foundation

/// FR13 — bounded proof subprocess result captured after worker settlement.
public struct RunProofResult: Codable, Equatable, Sendable {
    public var command: String
    public var exitCode: Int?
    public var passed: Bool
    public var timedOut: Bool
    public var outputTail: String

    public init(
        command: String, exitCode: Int?, passed: Bool, timedOut: Bool = false, outputTail: String
    ) {
        self.command = command
        self.exitCode = exitCode
        self.passed = passed
        self.timedOut = timedOut
        self.outputTail = outputTail
    }
}
