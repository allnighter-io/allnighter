import Foundation

/// Loopback HTTP to Ollama's local runtime (`127.0.0.1:11434` only).
///
/// Signal source: `ollama_local`. Remote `OLLAMA_HOST`, LAN, and Ollama Cloud
/// are out of this packet — this client never reads those.
///
/// Transport is injectable so tests never open a socket.
public enum OllamaLocalRuntimeClient {

    public static let sourceId = "ollama_local"
    public static let loopbackHost = "127.0.0.1"
    public static let loopbackPort = 11434
    public static let defaultTimeout: TimeInterval = 2.0
    public static let maxResponseBytes = 2_000_000

    public static let versionPath = "/api/version"
    public static let tagsPath = "/api/tags"
    public static let psPath = "/api/ps"

    public static var baseURL: URL {
        URL(string: "http://\(loopbackHost):\(loopbackPort)")!
    }

    public static func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    public protocol Transport: Sendable {
        func data(for request: URLRequest) throws -> (Data, URLResponse)
    }

    public enum FetchFailure: Sendable, Equatable {
        case timeout
        case network(String)
        case httpError(statusCode: Int)
        case responseTooLarge
        case unparseableBody
        case emptyBody
    }

    public struct FetchSuccess: Sendable, Equatable {
        public let data: Data
        public let statusCode: Int
    }

    public enum FetchResult: Sendable, Equatable {
        case success(FetchSuccess)
        case failure(FetchFailure)
    }

    public struct URLSessionTransport: Transport {
        public static let defaultConfiguration: URLSessionConfiguration = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = OllamaLocalRuntimeClient.defaultTimeout
            config.timeoutIntervalForResource = OllamaLocalRuntimeClient.defaultTimeout * 2
            config.httpCookieStorage = nil
            config.httpCookieAcceptPolicy = .never
            config.urlCache = nil
            return config
        }()

        private let session: URLSession

        public init(session: URLSession? = nil) {
            self.session = session ?? URLSession(configuration: Self.defaultConfiguration)
        }

        public func data(for request: URLRequest) throws -> (Data, URLResponse) {
            try session.ollamaLocalSyncData(for: request)
        }
    }

    public static func get(
        path: String,
        timeout: TimeInterval = defaultTimeout,
        transport: any Transport
    ) -> FetchResult {
        let url = endpoint(path)
        guard url.host == loopbackHost, url.port == loopbackPort else {
            return .failure(.network("refused non-loopback Ollama URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                return .failure(.timeout)
            }
            return .failure(.network(String(describing: error)))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.network("non-HTTP response"))
        }
        guard (200 ... 299).contains(http.statusCode) else {
            return .failure(.httpError(statusCode: http.statusCode))
        }
        guard data.count <= maxResponseBytes else {
            return .failure(.responseTooLarge)
        }
        guard !data.isEmpty else {
            return .failure(.emptyBody)
        }
        return .success(FetchSuccess(data: data, statusCode: http.statusCode))
    }
}

private extension URLSession {
    func ollamaLocalSyncData(for request: URLRequest) throws -> (Data, URLResponse) {
        final class Box: @unchecked Sendable {
            var result: Result<(Data, URLResponse), Error>?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                box.result = .failure(error)
            } else if let data, let response {
                box.result = .success((data, response))
            } else {
                box.result = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try box.result!.get()
    }
}
