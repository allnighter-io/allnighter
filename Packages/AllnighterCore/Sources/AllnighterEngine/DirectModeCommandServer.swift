import Foundation
import Darwin
import AllnighterCore

public enum DirectModeCommandError: Error, Equatable, Sendable {
    case inboxEntryMismatch(
        requestId: String,
        expectedAccountId: String,
        actualAccountId: String,
        expectedMacAgentId: String,
        actualMacAgentId: String
    )
}

public protocol DirectModeCommandHandling: Sendable {
    func handle(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandAckEnvelope
}

public struct DirectModeCommandHandler: DirectModeCommandHandling {
    private let accountId: String
    private let macAgentId: String
    private let router: any RemoteCommandRouting
    private let auditRecorder: any RemoteAuditRecording
    private let now: @Sendable () -> Date

    public init(
        accountId: String,
        macAgentId: String,
        router: any RemoteCommandRouting,
        auditRecorder: any RemoteAuditRecording = NoopRemoteAuditRecorder(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.router = router
        self.auditRecorder = auditRecorder
        self.now = now
    }

    public func handle(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandAckEnvelope {
        guard entry.accountId == accountId,
              entry.macAgentId == macAgentId else {
            throw DirectModeCommandError.inboxEntryMismatch(
                requestId: entry.requestId,
                expectedAccountId: accountId,
                actualAccountId: entry.accountId,
                expectedMacAgentId: macAgentId,
                actualMacAgentId: entry.macAgentId
            )
        }
        let result = try await router.route(entry)
        let envelope = RemoteCommandAckEnvelope(
            requestId: entry.requestId,
            accountId: entry.accountId,
            macAgentId: entry.macAgentId,
            ack: result.ack,
            auditEvent: result.auditEvent,
            createdAt: now()
        )
        try auditRecorder.record(envelope)
        return envelope
    }
}

public final class DirectModeCommandServer: @unchecked Sendable {
    public static let commandPath = "/remote/command"
    public static let pairingPath = "/remote/pair"

    private let lock = NSLock()
    private let handler: any DirectModeCommandHandling
    private let pairingHandler: (any DirectModePairingHandling)?
    private let maxRequestBytes: Int
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var boundPort: UInt16 = 0

    public init(
        handler: any DirectModeCommandHandling,
        pairingHandler: (any DirectModePairingHandling)? = nil,
        maxRequestBytes: Int = 512 * 1024
    ) {
        self.handler = handler
        self.pairingHandler = pairingHandler
        self.maxRequestBytes = max(1024, maxRequestBytes)
    }

    public var port: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return boundPort
    }

    public func start() throws -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD < 0 else { throw ServerError.alreadyRunning }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(errno) }
        defer { if listenFD < 0 { close(fd) } }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ServerError.bindFailed(errno) }
        guard listen(fd, SOMAXCONN) == 0 else { throw ServerError.listenFailed(errno) }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameResult == 0 else { throw ServerError.bindFailed(errno) }

        listenFD = fd
        boundPort = UInt16(bigEndian: bound.sin_port)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        acceptSource = source

        return boundPort
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        boundPort = 0
    }

    private func acceptConnections() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { break }
            Task.detached(priority: .userInitiated) { [weak self] in
                defer { close(client) }
                await self?.respond(on: client)
            }
        }
    }

    private func respond(on client: Int32) async {
        guard let request = readRequest(on: client) else {
            writeJSON(["error": "bad_request"], status: "400 Bad Request", to: client)
            return
        }
        guard request.method == "POST" else {
            writeJSON(["error": "not_found"], status: "404 Not Found", to: client)
            return
        }

        switch request.path {
        case Self.commandPath:
            do {
                let entry = try CoreJSON.decode(RemoteCommandInboxEntry.self, from: request.body)
                let envelope = try await handler.handle(entry)
                writeData(try CoreJSON.encode(envelope), status: "200 OK", to: client)
            } catch {
                writeJSON(["error": "bad_request"], status: "400 Bad Request", to: client)
            }
        case Self.pairingPath:
            guard let pairingHandler else {
                writeJSON(["error": "not_found"], status: "404 Not Found", to: client)
                return
            }
            do {
                let request = try CoreJSON.decode(DirectModePairingSubmitRequest.self, from: request.body)
                let response = try pairingHandler.handle(request)
                writeData(try CoreJSON.encode(response), status: "200 OK", to: client)
            } catch {
                writeJSON(["error": "bad_request"], status: "400 Bad Request", to: client)
            }
        default:
            writeJSON(["error": "not_found"], status: "404 Not Found", to: client)
        }
    }

    private func readRequest(on client: Int32) -> HTTPRequest? {
        var data = Data()
        let separator = Data("\r\n\r\n".utf8)
        var expectedLength: Int?

        while data.count < maxRequestBytes {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let readCount = buffer.withUnsafeMutableBytes { ptr in
                read(client, ptr.baseAddress, ptr.count)
            }
            guard readCount > 0 else { break }
            data.append(contentsOf: buffer.prefix(readCount))

            guard let separatorRange = data.range(of: separator) else { continue }
            if expectedLength == nil {
                let headerData = Data(data[..<separatorRange.lowerBound])
                guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
                expectedLength = contentLength(from: headerString)
            }
            let bodyStart = separatorRange.upperBound
            if data.count >= bodyStart + (expectedLength ?? 0) {
                break
            }
        }

        guard data.count <= maxRequestBytes,
              let separatorRange = data.range(of: separator),
              let headerString = String(data: Data(data[..<separatorRange.lowerBound]), encoding: .utf8) else {
            return nil
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let length = expectedLength ?? contentLength(from: headerString)
        let bodyStart = separatorRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        return HTTPRequest(
            method: parts[0],
            path: parts[1],
            body: data.subdata(in: bodyStart..<(bodyStart + length))
        )
    }

    private func contentLength(from headerString: String) -> Int {
        for line in headerString.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else {
                continue
            }
            return max(0, Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        }
        return 0
    }

    private func writeJSON(_ object: [String: String], status: String, to client: Int32) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        writeData(data, status: status, to: client)
    }

    private func writeData(_ body: Data, status: String, to client: Int32) {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json",
            "Connection: close",
            "Content-Length: \(body.count)",
            "",
            "",
        ].joined(separator: "\r\n")
        _ = header.withCString { write(client, $0, strlen($0)) }
        body.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                _ = write(client, base, body.count)
            }
        }
    }

    public enum ServerError: Error, Equatable {
        case alreadyRunning
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
    }

    private struct HTTPRequest {
        var method: String
        var path: String
        var body: Data
    }
}
