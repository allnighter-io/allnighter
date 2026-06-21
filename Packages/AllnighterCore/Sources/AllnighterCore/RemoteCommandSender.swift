import Foundation

public struct RemoteCommandSendResult: Equatable, Sendable {
    public var ack: CommandAck
    public var attemptCount: Int
    public var correctedClockAt: Date?

    public init(
        ack: CommandAck,
        attemptCount: Int,
        correctedClockAt: Date? = nil
    ) {
        self.ack = ack
        self.attemptCount = attemptCount
        self.correctedClockAt = correctedClockAt
    }
}

public enum RemoteCommandSender {
    public static func sendWithClockSkewRetry(
        client: any RemoteClient,
        initialNow: Date = Date(),
        maxClockSkewRetries: Int = 1,
        build: @Sendable (Date) throws -> RemoteCommand
    ) async throws -> RemoteCommandSendResult {
        let maxClockSkewRetries = max(0, maxClockSkewRetries)
        var attemptCount = 0
        var signingTime = initialNow
        var correctedClockAt: Date?

        while true {
            attemptCount += 1
            let command = try build(signingTime)
            let ack = try await client.send(command)
            guard !ack.accepted,
                  ack.reason == .clockSkew,
                  let serverTime = ack.serverTime,
                  attemptCount <= maxClockSkewRetries else {
                return RemoteCommandSendResult(
                    ack: ack,
                    attemptCount: attemptCount,
                    correctedClockAt: correctedClockAt
                )
            }
            correctedClockAt = serverTime
            signingTime = serverTime
        }
    }
}
