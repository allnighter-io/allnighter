import Foundation
import XCTest
@testable import AllnighterCore

final class RemoteSupabaseAuthClientTests: XCTestCase {
    func testSignInWithAppleExchangesIdentityToken() async throws {
        let transport = MockSupabaseHTTPTransport { request in
            XCTAssertTrue(request.url.absoluteString.contains("/auth/v1/token"))
            XCTAssertEqual(request.headers["apikey"], "publishable")
            let body = try XCTUnwrap(request.body)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
            XCTAssertEqual(json?["provider"], "apple")
            XCTAssertEqual(json?["id_token"], "apple-id-token")
            XCTAssertEqual(json?["nonce"], "nonce-raw")
            return SupabaseHTTPResponse(
                statusCode: 200,
                data: Data(
                    """
                    {
                      "access_token": "access.jwt.token",
                      "refresh_token": "refresh-token",
                      "expires_in": 3600,
                      "user": { "id": "user-123" }
                    }
                    """.utf8
                )
            )
        }

        let client = RemoteSupabaseAuthClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable",
            transport: transport
        )

        let session = try await client.signInWithApple(idToken: "apple-id-token", nonce: "nonce-raw")

        XCTAssertEqual(session.userId, "user-123")
        XCTAssertEqual(session.accessToken, "access.jwt.token")
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.provider, .apple)
    }
}

private struct MockSupabaseHTTPTransport: SupabaseHTTPTransport {
    var handler: @Sendable (SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse

    init(handler: @escaping @Sendable (SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse {
        try await handler(request)
    }
}
