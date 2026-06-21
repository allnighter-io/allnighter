import Foundation
import AllnighterCore

public enum DirectModePairingClientError: Error, Equatable, Sendable {
    case invalidEndpoint(String)
    case httpStatus(Int)
    case badResponse
}

public struct DirectModePairingClient: Sendable {
    private let endpoint: DirectModeEndpoint
    private let poster: any DirectModeHTTPPosting

    public init(
        endpoint: DirectModeEndpoint,
        poster: any DirectModeHTTPPosting = URLSessionDirectModeHTTPPoster()
    ) {
        self.endpoint = endpoint
        self.poster = poster
    }

    public func submit(
        _ request: DirectModePairingSubmitRequest
    ) async throws -> DirectModePairingSubmitResponse {
        let pairingURL = pairingURLString(baseURL: endpoint.baseURL)
        guard let url = URL(string: pairingURL) else {
            throw DirectModePairingClientError.invalidEndpoint(pairingURL)
        }
        let response = try await poster.postJSON(CoreJSON.encode(request), to: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DirectModePairingClientError.httpStatus(response.statusCode)
        }
        guard let decoded = try? CoreJSON.decode(DirectModePairingSubmitResponse.self, from: response.body) else {
            throw DirectModePairingClientError.badResponse
        }
        return decoded
    }

    private func pairingURLString(baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)\(DirectModeCommandServer.pairingPath)"
    }
}
