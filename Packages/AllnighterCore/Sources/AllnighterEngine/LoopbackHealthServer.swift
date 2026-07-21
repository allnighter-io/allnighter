import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Minimal loopback-only HTTP listener for coordinator health. Binds `127.0.0.1`
/// only; responds to `GET /health` with the caller-provided JSON body.
public final class LoopbackHealthServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var healthBody: (@Sendable () -> String)?
    private var boundPort: UInt16 = 0

    public init() {}

    public var port: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return boundPort
    }

    public func start(healthBody: @escaping @Sendable () -> String) throws -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD < 0 else { throw LoopbackError.alreadyRunning }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LoopbackError.socketFailed(errno) }
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
        guard bindResult == 0 else { throw LoopbackError.bindFailed(errno) }
        guard listen(fd, SOMAXCONN) == 0 else { throw LoopbackError.listenFailed(errno) }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameResult == 0 else { throw LoopbackError.bindFailed(errno) }

        self.healthBody = healthBody
        self.listenFD = fd
        self.boundPort = UInt16(bigEndian: bound.sin_port)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        self.acceptSource = source

        return boundPort
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        boundPort = 0
        healthBody = nil
    }

    private func acceptConnections() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { break }
            defer { close(client) }
            respond(on: client)
        }
    }

    private func respond(on client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readCount = buffer.withUnsafeMutableBytes { ptr in
            read(client, ptr.baseAddress, ptr.count)
        }
        guard readCount > 0 else { return }
        let request = String(decoding: buffer.prefix(readCount), as: UTF8.self)
        let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let body: String
        let status: String
        if firstLine.hasPrefix("GET /health") {
            body = lock.withLock { healthBody?() ?? "{}" }
            status = "200 OK"
        } else {
            body = "{\"error\":\"not found\"}"
            status = "404 Not Found"
        }
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Connection: close\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        _ = response.withCString { write(client, $0, strlen($0)) }
    }

    public enum LoopbackError: Error, Equatable {
        case alreadyRunning
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
