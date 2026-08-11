import Foundation

/// One-shot `GET /health` against `127.0.0.1` only. The transport is injected so
/// no test opens a socket. Failure modes are distinct because connection refused,
/// timeout, non-200, and unparseable body mean different things to a user.
public struct ServeHealthClient: Sendable {

    public typealias Transport = @Sendable (URLRequest, TimeInterval) throws -> (Data, Int)

    public let transport: Transport

    public init(transport: Transport? = nil) {
        self.transport = transport ?? Self.defaultTransport
    }

    public struct Response: Equatable, Sendable {
        public let daemonId: String
        public let pid: Int32

        public init(daemonId: String, pid: Int32) {
            self.daemonId = daemonId
            self.pid = pid
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case nonLoopbackHost(String)
        case connectionRefused(String)
        case timeout(String)
        case non200Status(Int, String)
        case unparseableBody(String)
    }

    public func probe(host: String, port: UInt16, timeout: TimeInterval = 2.0) -> Result<Response, Failure> {
        let address = "\(host):\(port)"
        guard host == "127.0.0.1" || host == "localhost" else {
            return .failure(.nonLoopbackHost(address))
        }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        request.timeoutInterval = timeout

        do {
            let (data, statusCode) = try transport(request, timeout)
            guard statusCode == 200 else {
                return .failure(.non200Status(statusCode, address))
            }
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.unparseableBody("body is not valid JSON"))
            }
            guard let daemonId = dict["daemonId"] as? String else {
                return .failure(.unparseableBody("missing daemonId field"))
            }
            let pid: Int32
            if let p = dict["pid"] as? Int32 {
                pid = p
            } else if let p = dict["pid"] as? Int {
                pid = Int32(p)
            } else {
                return .failure(.unparseableBody("missing pid field"))
            }
            return .success(Response(daemonId: daemonId, pid: pid))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut:
                    return .failure(.timeout(address))
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                    return .failure(.connectionRefused(address))
                default:
                    return .failure(.connectionRefused("\(address): \(nsError.localizedDescription)"))
                }
            }
            return .failure(.connectionRefused("\(address): \(error.localizedDescription)"))
        }
    }

    private static let defaultTransport: Transport = { request, timeout in
        var mutableRequest = request
        mutableRequest.timeoutInterval = timeout
        let semaphore = DispatchSemaphore(value: 0)
        let box = TransportResultBox()
        let task = URLSession.shared.dataTask(with: mutableRequest) { data, response, error in
            box.lock.lock()
            if let error = error {
                box.thrown = error
            } else if let httpResponse = response as? HTTPURLResponse {
                box.result = (data ?? Data(), httpResponse.statusCode)
            } else {
                box.thrown = NSError(domain: "ServeHealthClient", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "not an HTTP response"])
            }
            box.lock.unlock()
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        box.lock.lock()
        let result = box.result
        let thrown = box.thrown
        box.lock.unlock()
        if let error = thrown { throw error }
        return result ?? (Data(), -1)
    }
}

private final class TransportResultBox: @unchecked Sendable {
    let lock = NSLock()
    var result: (Data, Int)?
    var thrown: Error?
}
