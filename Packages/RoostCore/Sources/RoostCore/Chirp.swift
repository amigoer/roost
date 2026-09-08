import Foundation

/// A short 8-bit voice, synthesised rather than bundled.
///
/// Square waves and a handful of notes, for the same reason the mascot is a
/// pixel grid: it is the idiom the app already speaks, it costs nothing in the
/// bundle, and at this length nobody wants a sample anyway.
///
/// Pitch carries the meaning, not loudness. Rising is something that needs you,
/// falling is something that is finished, and the two are told apart across a
/// room without being listened to.
public struct Chirp: Sendable, Hashable {
    public struct Note: Sendable, Hashable {
        public let hertz: Double
        public let seconds: Double

        public init(_ hertz: Double, _ seconds: Double = 0.07) {
            self.hertz = hertz
            self.seconds = seconds
        }
    }

    public let notes: [Note]

    public init(_ notes: [Note]) {
        self.notes = notes
    }

    /// Something has stopped and only you can start it again. Rising, and the
    /// only one of these with a third note: it is the one that has to carry.
    public static let waiting = Chirp([Note(784), Note(1046), Note(1318, 0.1)])
    /// A turn ended. Falling, quiet, over quickly.
    public static let done = Chirp([Note(659), Note(523, 0.09)])

    public var duration: TimeInterval { notes.reduce(0) { $0 + $1.seconds } }

    // MARK: - Rendering

    public static let sampleRate: Double = 22_050
    /// Well under full scale. This plays over whatever the user is listening
    /// to, and a notification that has to be turned down is one that gets
    /// turned off.
    static let amplitude: Double = 0.18

    /// A 16-bit mono WAV, ready to hand to a player.
    public func wav(sampleRate: Double = Chirp.sampleRate) -> Data {
        let samples = render(sampleRate: sampleRate)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))          // PCM header length
        data.append(littleEndian: UInt16(1))           // PCM
        data.append(littleEndian: UInt16(1))           // mono
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * 2))
        data.append(littleEndian: UInt16(2))           // block align
        data.append(littleEndian: UInt16(16))          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: UInt32(samples.count * 2))
        for sample in samples { data.append(littleEndian: UInt16(bitPattern: sample)) }
        return data
    }

    func render(sampleRate: Double) -> [Int16] {
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.seconds * sampleRate)
            guard count > 0 else { continue }
            let period = sampleRate / note.hertz
            for index in 0..<count {
                // Linear decay across the note. A square wave cut off mid-cycle
                // is a click, and a click is what makes a chirp sound broken.
                let envelope = 1 - Double(index) / Double(count)
                let square: Double = index.truncatingRemainder(period) < period / 2 ? 1 : -1
                samples.append(Int16(square * Self.amplitude * envelope * 32_767))
            }
        }
        return samples
    }
}

private extension Int {
    func truncatingRemainder(_ divisor: Double) -> Double {
        Double(self).truncatingRemainder(dividingBy: divisor)
    }
}

private extension Data {
    mutating func append<Value: FixedWidthInteger>(littleEndian value: Value) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
