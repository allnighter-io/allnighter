import XCTest
import AllnighterCore

final class RemoteSupabaseEnvironmentTests: XCTestCase {
    func testLoadRequiresURLAndPublishableKey() {
        XCTAssertNil(RemoteSupabaseEnvironment.load(from: [:]))
        XCTAssertNil(RemoteSupabaseEnvironment.load(from: [
            "ALLNIGHTER_SUPABASE_URL": "https://example.supabase.co",
        ]))
    }

    func testLoadParsesMacAndDeviceCredentials() throws {
        let environment = try XCTUnwrap(RemoteSupabaseEnvironment.load(from: [
            "ALLNIGHTER_SUPABASE_URL": "https://example.supabase.co",
            "ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY": "publishable",
            "ALLNIGHTER_SUPABASE_ACCESS_TOKEN": "mac-token",
            "ALLNIGHTER_SUPABASE_DEVICE_ACCESS_TOKEN": "device-token",
            "ALLNIGHTER_REMOTE_ACCOUNT_ID": "acct_1",
            "ALLNIGHTER_REMOTE_ACCOUNT_PROVIDER": "google",
            "ALLNIGHTER_REMOTE_MAC_AGENT_ID": "mac_1",
            "ALLNIGHTER_REMOTE_MAC_DISPLAY_NAME": "Studio",
        ]))

        XCTAssertEqual(environment.supabaseURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(environment.publishableKey, "publishable")
        XCTAssertEqual(environment.accessToken, "mac-token")
        XCTAssertEqual(environment.deviceAccessToken, "device-token")
        XCTAssertEqual(environment.accountId, "acct_1")
        XCTAssertEqual(environment.accountProvider, .google)
        XCTAssertEqual(environment.macAgentId, "mac_1")
        XCTAssertEqual(environment.macDisplayName, "Studio")
        XCTAssertTrue(environment.hasMacAgentCredentials)
        XCTAssertTrue(environment.hasDeviceCredentials)
        XCTAssertEqual(environment.macAccountSession()?.provider, .google)
        XCTAssertEqual(environment.deviceAccessTokenValue(), "device-token")
    }
}
