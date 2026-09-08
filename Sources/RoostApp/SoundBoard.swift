import AVFoundation
import RoostCore

/// Plays what the announcer decided, and remembers whether it is wanted.
///
/// Off until it is switched on: a menu-bar-less app that starts making noises
/// on first launch has spent the user's patience before it has explained
/// itself.
@MainActor
final class SoundBoard {
    static let key = "playsSounds"

    var isOn = UserDefaults.standard.bool(forKey: SoundBoard.key) {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.key) }
    }

    private var announcer = Announcer()
    /// Rendered once each. They never change, and rendering on every state
    /// change would be work done in the path of a state change.
    private var rendered: [Chirp: AVAudioPlayer] = [:]

    /// Always called, switched on or not: an announcer that only sees some of
    /// the snapshots would chirp for a transition the user already watched
    /// happen while sound was off.
    func observe(_ sessions: [Session]) {
        guard let chirp = announcer.cue(for: sessions), isOn else { return }
        play(chirp)
    }

    func play(_ chirp: Chirp) {
        guard let player = rendered[chirp] ?? make(chirp) else { return }
        rendered[chirp] = player
        player.currentTime = 0
        player.play()
    }

    private func make(_ chirp: Chirp) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: chirp.wav()) else { return nil }
        player.prepareToPlay()
        return player
    }
}
