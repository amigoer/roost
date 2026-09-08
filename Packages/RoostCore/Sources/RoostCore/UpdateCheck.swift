import Foundation

public struct ReleaseInfo: Sendable, Equatable {
    /// Without the leading `v`, to match `CFBundleShortVersionString`.
    public let version: String
    public let page: URL

    public init(version: String, page: URL) {
        self.version = version
        self.page = page
    }
}

/// Looks for a newer published build.
///
/// This is the only request Roost makes. It asks a public endpoint what the
/// latest release is and sends nothing about the machine or its sessions, and
/// it can be switched off from the menu.
///
/// Detection only: the app is ad-hoc signed rather than notarised, and
/// installing an update over itself without a signature to check is not
/// something an app should do quietly.
public enum UpdateCheck {
    public static let endpoint = URL(string: "https://api.github.com/repos/amigoer/roost/releases/latest")!

    /// Rare enough to be invisible, often enough to notice a release the same day.
    public static let interval: TimeInterval = 6 * 60 * 60

    /// Component by component, numerically. Anything unparseable loses, so a
    /// malformed reply can never be mistaken for an update.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard candidate.contains(where: \.isNumber) else { return false }
        let new = components(candidate), old = components(current)
        for index in 0..<max(new.count, old.count) {
            let left = index < new.count ? new[index] : 0
            let right = index < old.count ? old[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            // "0.2.0-beta" is still 0.2.0 for ordering purposes.
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// Pure parse, so the shape of the reply is testable without the network.
    public static func release(from data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true,
              json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return ReleaseInfo(version: String(tag.trimmingPrefix("v")), page: page)
    }

    public static func fetch(from url: URL = endpoint) async -> ReleaseInfo? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return release(from: data)
    }
}
