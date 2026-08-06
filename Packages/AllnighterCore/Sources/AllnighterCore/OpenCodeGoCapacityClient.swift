import Foundation

/// HTTP fetch for the OpenCode Go `/go` dashboard (dogfood spike).
public enum OpenCodeGoCapacityClient {

    public static let dashboardURLPrefix = "https://opencode.ai/workspace/"
    public static let dashboardURLSuffix = "/go"
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Gecko/20100101 Firefox/148.0"
    public static let defaultTimeout: TimeInterval = 10
    public static let maxResponseBytes = 2_000_000

    public enum FetchFailure: Sendable, Equatable {
        case authRequired(statusCode: Int)
        case httpError(statusCode: Int)
        case timeout
        case network(String)
        case responseTooLarge
        case unexpectedContentType
        case finalURLMismatch
    }

    public struct FetchSuccess: Sendable, Equatable {
        public let html: String
        public let statusCode: Int
        public let finalURL: URL
        public let contentType: String?
        public let byteCount: Int
    }

    public enum FetchResult: Sendable, Equatable {
        case success(FetchSuccess)
        case failure(FetchFailure)
    }

    /// Injectable transport for tests — production uses `URLSession.shared`.
    public protocol Transport: Sendable {
        func data(for request: URLRequest) throws -> (Data, URLResponse)
    }

    public struct URLSessionTransport: Transport {
        private let session: URLSession
        public init(session: URLSession = .shared) { self.session = session }
        public func data(for request: URLRequest) throws -> (Data, URLResponse) {
            try session.syncData(for: request)
        }
    }

    public static func dashboardURL(workspaceId: String) -> URL? {
        let encoded = workspaceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workspaceId
        return URL(string: "\(dashboardURLPrefix)\(encoded)\(dashboardURLSuffix)")
    }

    public static func fetch(
        workspaceId: String,
        authCookie: String,
        timeout: TimeInterval = defaultTimeout,
        transport: any Transport = URLSessionTransport()
    ) -> FetchResult {
        guard let url = dashboardURL(workspaceId: workspaceId) else {
            return .failure(.network("invalid workspace id"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("auth=\(authCookie)", forHTTPHeaderField: "Cookie")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout)
        } catch {
            return .failure(.network(String(describing: error)))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.network("non-HTTP response"))
        }
        let status = http.statusCode
        if status == 401 || status == 403 {
            return .failure(.authRequired(statusCode: status))
        }
        guard (200 ... 299).contains(status) else {
            return .failure(.httpError(statusCode: status))
        }

        guard let finalURL = http.url else {
            return .failure(.network("missing final URL"))
        }
        if isSignInURL(finalURL) {
            return .failure(.authRequired(statusCode: status))
        }
        guard finalURL.path.hasSuffix("/go") else {
            return .failure(.finalURLMismatch)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        if let contentType, !contentType.lowercased().contains("text/html") {
            return .failure(.unexpectedContentType)
        }
        guard data.count <= maxResponseBytes else {
            return .failure(.responseTooLarge)
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return .failure(.network("empty body"))
        }
        return .success(
            FetchSuccess(
                html: html,
                statusCode: status,
                finalURL: finalURL,
                contentType: contentType,
                byteCount: data.count
            )
        )
    }

    private static func isSignInURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/sign-in") || path.contains("/login") || path.contains("/auth/")
    }
}

// MARK: - Sync URLSession (capacity path is synchronous today)

private extension URLSession {
    func syncData(for request: URLRequest) throws -> (Data, URLResponse) {
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
