import Foundation

/// The last reading, kept across launches.
///
/// Without this the figure goes when the app does, and goes again a quarter of
/// an hour after the last report -- which is exactly the moment someone opens
/// the island to ask how much is left. Keeping it lets the panel answer with a
/// number and the time it was true, rather than with nothing.
public enum UsageStore {
    public static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Roost/usage.json")
    }

    public static func load(from url: URL = fileURL) -> Usage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.wire.decode(Usage.self, from: data)
    }

    /// Best effort in both directions. A reading that will not write is worth
    /// no noise: the one in memory is still on screen, and the next report
    /// tries again within the minute.
    public static func save(_ usage: Usage, to url: URL = fileURL) {
        guard let data = try? JSONEncoder.wire.encode(usage) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Switching the figure off takes the copy on disk with it. Leaving it
    /// behind would mean a number nobody asked for reappearing at next launch.
    public static func clear(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
