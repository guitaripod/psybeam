import AVFoundation

/// A short rising two-note chime — the audible "your turn, speak now" cue for the
/// person across the table. Synthesized to PCM in-process (no bundled asset) and
/// played into the WebRTC-owned audio session, so VPIO echo-cancellation keeps it
/// out of the captured audio.
@MainActor
final class Earcon {
    private let player: AVAudioPlayer?

    init() {
        player = Self.makeChime().flatMap { try? AVAudioPlayer(data: $0) }
        player?.volume = 1.0
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func makeChime() -> Data? {
        let sampleRate = 44_100.0
        let notes: [(frequency: Double, duration: Double)] = [(523.25, 0.09), (783.99, 0.14)]
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.duration * sampleRate)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let value = sin(2.0 * .pi * note.frequency * t) * envelope(i, count) * 0.5
                samples.append(Int16(max(-1.0, min(1.0, value)) * 32_767))
            }
        }
        return wav(samples, sampleRate: Int(sampleRate))
    }

    private static func envelope(_ i: Int, _ count: Int) -> Double {
        let attack = max(1, min(count / 8, 220))
        let release = max(1, min(count / 2, 1_300))
        if i < attack { return Double(i) / Double(attack) }
        if i > count - release { return Double(count - i) / Double(release) }
        return 1.0
    }

    private static func wav(_ samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let dataSize = samples.count * 2
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(dataSize))
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        return data
    }
}
