import Foundation
import Security

/// The OAuth credential Claude Code keeps for itself.
public struct OAuthCredential: Sendable, Hashable {
    public let accessToken: String
    public let expiresAt: Date
    /// What the account is on. Used only to explain an empty answer: an account
    /// billed by API key has no quota windows to report at all.
    public let subscriptionType: String?

    public init(accessToken: String, expiresAt: Date, subscriptionType: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    public func isValid(now: Date = Date()) -> Bool { expiresAt > now }
}

/// Claude Code's credential, read and never written.
///
/// Roost does not refresh it. Claude Code owns the keychain item and rotates it
/// on its own schedule; a second process spending the refresh token would be
/// two writers racing for one entry, and losing that race breaks a login -- an
/// absurd price for a number in a footer. An expired token is therefore simply
/// no credential, and the caller falls back to whatever a status line last said
/// until Claude Code next runs and rotates it.
///
/// Reading it raises a keychain prompt the first time, because the item belongs
/// to another application. Ad-hoc signing means a new build is a new identity,
/// so the prompt comes back after an update. That is the honest cost of the
/// figure, and the switch that turns this on says so.
public enum Credentials {
    /// The item Claude Code writes. Its account is the macOS user, so the
    /// service alone identifies it.
    public static let service = "Claude Code-credentials"

    /// The same JSON, where Claude Code puts it when there is no keychain to
    /// write to. Read second: a machine with both has the keychain as the live
    /// one and the file as a leftover.
    public static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/.credentials.json")
    }

    public static func oauth() -> OAuthCredential? {
        (keychain() ?? (try? Data(contentsOf: fileURL))).flatMap(oauth(from:))
    }

    /// Pure parse, so the shape is testable without a keychain.
    public static func oauth(from data: Data) -> OAuthCredential? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let block = json["claudeAiOauth"] as? [String: Any],
              let token = block["accessToken"] as? String, !token.isEmpty,
              let expiry = expiry(block["expiresAt"])
        else { return nil }
        return OAuthCredential(accessToken: token, expiresAt: expiry,
                               subscriptionType: block["subscriptionType"] as? String)
    }

    /// Milliseconds in the build that writes it today; seconds are read too, on
    /// the same reasoning as a reset time. Guessing wrong either expires a live
    /// credential in 1970 or holds a dead one until the year 58000.
    static func expiry(_ raw: Any?) -> Date? {
        guard let value = raw as? Double, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
    }

    static func keychain() -> Data? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
        else { return nil }
        return item as? Data
    }
}

/// The credential Roost has already been given, held for as long as it is good
/// for.
///
/// Reading another application's keychain item raises a prompt for any build
/// that is not on that item's access list, and ad-hoc signing puts every build
/// on an identity of its own -- so "always allow" lasts exactly until the next
/// update, and a developer rebuilding is a new application every time. Polling
/// read it fresh on every tick, which turned one grant into a dialog a minute.
///
/// One read while the token is good is the whole of what the figure costs.
public actor CredentialStore {
    public static let shared = CredentialStore()

    /// How long a missing or expired credential is left alone before looking
    /// again. Claude Code owns the item and rotates it on its own schedule with
    /// nothing to tell Roost when; asking more often than this buys nothing but
    /// prompts.
    public static let recheckAfter: TimeInterval = 15 * 60

    private let read: @Sendable () -> OAuthCredential?
    private var held: OAuthCredential?
    private var lookedAt: Date = .distantPast

    public init(read: @escaping @Sendable () -> OAuthCredential? = { Credentials.oauth() }) {
        self.read = read
    }

    /// The credential, if there is a good one. Reads the keychain only when
    /// what is held has run out and the wait since the last look has passed.
    public func current(now: Date = Date()) -> OAuthCredential? {
        if let held, held.isValid(now: now) { return held }
        guard now.timeIntervalSince(lookedAt) >= Self.recheckAfter else { return nil }
        lookedAt = now
        held = read()
        guard let held, held.isValid(now: now) else { return nil }
        return held
    }

    /// Look now. For the moment the switch is turned on: someone has just asked
    /// for the figure, so the wait is not theirs to serve.
    public func refresh(now: Date = Date()) -> OAuthCredential? {
        lookedAt = .distantPast
        return current(now: now)
    }
}
