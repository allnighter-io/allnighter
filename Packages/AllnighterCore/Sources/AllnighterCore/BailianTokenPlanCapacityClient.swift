import Foundation

/// HTTP fetch for Alibaba Token Plan Personal (intl) rolling-window usage.
public enum BailianTokenPlanCapacityClient {

    public static let quotaHost = "bailian-singapore-cs.alibabacloud.com"
    public static let dashboardHost = "modelstudio.console.alibabacloud.com"
    public static let usageAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
    public static let gatewayAction = "IntlBroadScopeAspnGateway"
    public static let gatewayProduct = "sfm_bailian"
    public static let regionID = "ap-southeast-1"
    public static let consoleSite = "MODELSTUDIO_ALBABACLOUD"
    public static let dashboardURL =
        "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=plan#/efm/subscription/token-plan/personal"
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    public static let defaultTimeout: TimeInterval = 20
    public static let maxResponseBytes = 1_000_000

    public enum FetchFailure: Sendable, Equatable {
        case authRequired(statusCode: Int)
        case httpError(statusCode: Int)
        case timeout
        case network(String)
        case responseTooLarge
        case unexpectedContentType
        case finalURLHostMismatch
    }

    public struct FetchSuccess: Sendable, Equatable {
        public let json: Data
        public let statusCode: Int
        public let finalURL: URL
        public let contentType: String?
        public let byteCount: Int
    }

    public enum FetchResult: Sendable, Equatable {
        case success(FetchSuccess)
        case failure(FetchFailure)
    }

    public protocol Transport: Sendable {
        func data(for request: URLRequest) throws -> (Data, URLResponse)
    }

    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let expectedHost: String

        init(expectedHost: String) {
            self.expectedHost = expectedHost
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            if let host = request.url?.host, host != expectedHost {
                completionHandler(nil)
            } else {
                completionHandler(request)
            }
        }
    }

    public struct URLSessionTransport: Transport {
        public static let defaultConfiguration: URLSessionConfiguration = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = BailianTokenPlanCapacityClient.defaultTimeout
            config.timeoutIntervalForResource = BailianTokenPlanCapacityClient.defaultTimeout * 2
            config.httpShouldSetCookies = false
            config.urlCache = nil
            return config
        }()

        private let session: URLSession

        public init(configuration: URLSessionConfiguration = defaultConfiguration) {
            let delegate = RedirectGuard(expectedHost: BailianTokenPlanCapacityClient.quotaHost)
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }

        public func data(for request: URLRequest) throws -> (Data, URLResponse) {
            try session.syncData(for: request)
        }
    }

    public static func fetch(
        cookieHeader: String,
        transport: any Transport = URLSessionTransport()
    ) -> FetchResult {
        guard let url = usageURL() else {
            return .failure(.network("invalid URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
        request.httpBody = requestBody(cookieHeader: cookieHeader)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://\(dashboardHost)", forHTTPHeaderField: "Origin")
        request.setValue(dashboardURL, forHTTPHeaderField: "Referer")
        if let csrf = cookieValue(named: "login_aliyunid_csrf", in: cookieHeader) {
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token")
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout)
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.network("non-http response"))
        }
        guard let finalHost = http.url?.host, finalHost == quotaHost else {
            return .failure(.finalURLHostMismatch)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure(.authRequired(statusCode: http.statusCode))
        }
        guard (200...299).contains(http.statusCode) else {
            return .failure(.httpError(statusCode: http.statusCode))
        }
        if data.count > maxResponseBytes {
            return .failure(.responseTooLarge)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        if let contentType, !contentType.lowercased().contains("json"), !contentType.lowercased().contains("text") {
            return .failure(.unexpectedContentType)
        }
        return .success(
            FetchSuccess(
                json: data,
                statusCode: http.statusCode,
                finalURL: http.url ?? url,
                contentType: contentType,
                byteCount: data.count
            )
        )
    }

    static func usageURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = quotaHost
        components.path = "/data/api.json"
        components.queryItems = [
            URLQueryItem(name: "action", value: gatewayAction),
            URLQueryItem(name: "product", value: gatewayProduct),
            URLQueryItem(name: "api", value: usageAPI),
            URLQueryItem(name: "_v", value: "undefined"),
        ]
        return components.url
    }

    static func requestBody(cookieHeader: String) -> Data {
        var cornerstone: [String: Any] = [
            "feTraceId": UUID().uuidString.lowercased(),
            "feURL": dashboardURL,
            "protocol": "V2",
            "console": "ONE_CONSOLE",
            "productCode": "p_efm",
            "switchUserType": 3,
            "domain": dashboardHost,
            "consoleSite": consoleSite,
            "userNickName": "",
            "userPrincipalName": "",
            "xsp_lang": "en-US",
        ]
        if let anonymousID = cookieValue(named: "cna", in: cookieHeader), !anonymousID.isEmpty {
            cornerstone["X-Anonymous-Id"] = anonymousID
        }
        let params: [String: Any] = [
            "Api": usageAPI,
            "V": "1.0",
            "Data": ["cornerstoneParam": cornerstone],
        ]
        let paramsJSON = (try? JSONSerialization.data(withJSONObject: params))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "product", value: gatewayProduct),
            URLQueryItem(name: "action", value: gatewayAction),
            URLQueryItem(name: "region", value: regionID),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "params", value: paramsJSON),
        ]
        return Data((body.percentEncodedQuery ?? "").utf8)
    }

    static func cookieValue(named name: String, in header: String) -> String? {
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            guard key == name else { continue }
            return String(trimmed[trimmed.index(after: eq)...])
        }
        return nil
    }
}

private extension URLSession {
    func syncData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        switch result {
        case .success(let pair): return pair
        case .failure(let error): throw error
        case .none: throw URLError(.unknown)
        }
    }
}
