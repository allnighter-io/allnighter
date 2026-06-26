import Foundation

/// Public Supabase relay endpoints embedded in the app bundle or dev env.
/// The publishable key is safe to ship; access tokens stay in the session store.
public enum RemoteSupabasePublicConfig: Equatable, Sendable {
    public static let defaultProjectURL = URL(string: "https://kfqwpozmntqpxiveafld.supabase.co")!

    public struct Values: Equatable, Sendable {
        public var supabaseURL: URL
        public var publishableKey: String

        public init(supabaseURL: URL, publishableKey: String) {
            self.supabaseURL = supabaseURL
            self.publishableKey = publishableKey
        }
    }

    public static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Values? {
        if let fromEnvironment = loadFromEnvironment(environment) {
            return fromEnvironment
        }
        return loadFromBundle(bundle)
    }

    public static func loadFromEnvironment(_ environment: [String: String]) -> Values? {
        guard let urlString = trimmed(environment["ALLNIGHTER_SUPABASE_URL"]),
              let url = URL(string: urlString),
              url.scheme != nil,
              url.host != nil,
              let publishableKey = trimmed(environment["ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY"])
        else {
            return nil
        }
        return Values(supabaseURL: url, publishableKey: publishableKey)
    }

    private static func loadFromBundle(_ bundle: Bundle) -> Values? {
        let urlString = bundle.object(forInfoDictionaryKey: "ALLNIGHTER_SUPABASE_URL") as? String
            ?? defaultProjectURL.absoluteString
        guard let url = URL(string: urlString),
              url.scheme != nil,
              url.host != nil,
              let publishableKey = trimmed(bundle.object(forInfoDictionaryKey: "ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY") as? String)
        else {
            return nil
        }
        return Values(supabaseURL: url, publishableKey: publishableKey)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
