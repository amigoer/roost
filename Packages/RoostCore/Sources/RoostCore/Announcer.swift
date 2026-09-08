import Foundation

/// Decides what a refresh has earned out loud.
///
/// State, not events: a scan is a snapshot, so a voice has to come from the
/// difference between two of them. Levels rather than exact states, because a
/// session can move between two kinds of blocked while it waits and none of
/// that is worth a second noise.
public struct Announcer: Sendable {
    public init() {}

    private var known: [String: SignalLevel] = [:]
    /// The first snapshot is silent. Everything in it was already true before
    /// the app opened, and announcing a whole fleet at launch is how a sound
    /// becomes one nobody keeps on.
    private var hasBaseline = false

    public mutating func cue(for sessions: [Session]) -> Chirp? {
        var levels: [String: SignalLevel] = [:]
        var needsYou = false
        var finished = false

        for session in sessions {
            let level = session.state.signalLevel
            levels[session.id] = level
            guard hasBaseline else { continue }
            let before = known[session.id]

            if level == .blocked, before != .blocked {
                needsYou = true
            } else if level == .done, before == .running {
                finished = true
            }
        }

        known = levels
        guard hasBaseline else {
            hasBaseline = true
            return nil
        }

        // One noise per refresh, and the one that needs a person wins. Two
        // chirps on top of each other say less than either of them alone.
        if needsYou { return .waiting }
        return finished ? .done : nil
    }
}
