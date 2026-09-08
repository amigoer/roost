import Foundation

/// Asks Anthropic what is left of the account's quota windows.
///
/// The only path to the figure that does not need a session to render a status
/// line first, which is most of the time: the desktop app renders none at all,
/// and a Mac with nothing running renders none either. It is also the only
/// thing Roost sends anywhere besides the update check, so it is off until it
/// is switched on, and the switch says what this asks and of whom.
///
/// Reads `limits` rather than the windows named beside it. That array is the
/// shape the server extends -- a new kind of window arrives as another entry
/// with a `kind` nobody here has to have heard of, where a new top-level key
/// would simply go unread -- and it is the only place the per-model weeklies
/// and the server's own severity appear.
public enum UsageAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The header the endpoint sits behind, as the official client sends it.
    static let beta = "oauth-2025-04-20"

    /// The two entries in `limits` that mean the windows the island shows.
    static let fiveHourKind = "session"
    static let sevenDayKind = "weekly_all"
    static let scopedKind = "weekly_scoped"

    /// While someone is looking. Finer than the figure moves, but this is the
    /// moment the number is being read, so it is the moment to be right.
    public static let watchedInterval: TimeInterval = 60
    /// Otherwise. Enough to notice a window turning over without asking all day.
    public static let restingInterval: TimeInterval = 5 * 60
    /// Where backing off stops. Past this a refusal is a condition, not a blip,
    /// and asking harder will not fix it.
    public static let backoffCap: TimeInterval = 15 * 60

    /// Doubling from the resting interval, capped. `failures` is how many asks
    /// in a row went unanswered, so zero is the ordinary cadence.
    public static func delay(watched: Bool, failures: Int) -> TimeInterval {
        guard failures > 0 else { return watched ? watchedInterval : restingInterval }
        return min(backoffCap, restingInterval * pow(2, Double(failures - 1)))
    }

    /// Pure parse, so the shape of the reply is testable without the network.
    public static func usage(from data: Data, now: Date = Date()) -> Usage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let limits = (json["limits"] as? [[String: Any]]) ?? []

        let usage = Usage(fiveHour: window(fiveHourKind, in: limits, lockedBy: "five_hour", of: json),
                          sevenDay: window(sevenDayKind, in: limits, lockedBy: "seven_day", of: json),
                          scoped: scoped(in: limits),
                          source: .api,
                          reportedAt: now)
        return usage.isEmpty ? nil : usage
    }

    public static func fetch(credential: OAuthCredential, from url: URL = endpoint,
                             now: Date = Date()) async -> Usage? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(beta, forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return usage(from: data, now: now)
    }

    /// The lock lives on the window named at the top level rather than in
    /// `limits`, so it is read from there and nowhere else.
    static func window(_ kind: String, in limits: [[String: Any]],
                       lockedBy name: String, of json: [String: Any]) -> UsageWindow? {
        guard let entry = limits.first(where: { $0["kind"] as? String == kind }),
              let percent = entry["percent"] as? Double else { return nil }
        return UsageWindow(used: percent / 100,
                           resetsAt: Usage.resetDate(entry["resets_at"]),
                           lockedReason: (json[name] as? [String: Any])?["locked_reason"] as? String)
    }

    /// A scope with no name it can be shown under is dropped: a bar labelled
    /// nothing explains nothing.
    static func scoped(in limits: [[String: Any]]) -> [ScopedWindow] {
        limits.filter { $0["kind"] as? String == scopedKind }.compactMap { entry in
            guard let percent = entry["percent"] as? Double,
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let label = model["display_name"] as? String, !label.isEmpty
            else { return nil }
            return ScopedWindow(label: label,
                                window: UsageWindow(used: percent / 100,
                                                    resetsAt: Usage.resetDate(entry["resets_at"])))
        }
    }
}
