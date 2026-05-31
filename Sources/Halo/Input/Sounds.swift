import AVFoundation

/// Soft, synthesized UI cues for the wheel — short sine blips with a smooth
/// attack/decay envelope, kept quiet. There are no audio assets: each cue's buffer
/// is generated once at init. Playback is gated by `isEnabled` (the config toggle).
final class Sounds {
    static let shared = Sounds()

    enum Cue { case summon, select, fire, send, cancel }

    /// Wired by `AppController` to read `config.sounds`.
    var isEnabled: () -> Bool = { true }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var started = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers[.summon] = chord([392, 588], 0.11, 0.16)   // soft two-note bloom
        buffers[.select] = chord([720],      0.030, 0.06)  // whisper tick
        buffers[.fire]   = chord([523],      0.06, 0.15)   // crisp confirm
        buffers[.send]   = chord([523, 784], 0.15, 0.14)   // gentle rising "sent"
        buffers[.cancel] = chord([294],      0.11, 0.11)   // low, soft
    }

    func play(_ cue: Cue) {
        guard isEnabled(), let buffer = buffers[cue] else { return }
        DispatchQueue.main.async { [self] in
            startIfNeeded()
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        do { try engine.start(); player.play(); started = true } catch { /* no output → silent */ }
    }

    /// Sum of sine partials with a fast attack and exponential decay to silence.
    private func chord(_ freqs: [Double], _ duration: Double, _ volume: Double) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        let attack = max(1.0, 0.008 * sampleRate)
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            var value = 0.0
            for f in freqs { value += sin(2 * .pi * f * t) }
            value /= Double(freqs.count)
            let env = Double(i) < attack ? Double(i) / attack : exp(-4.0 * (t / duration))
            samples[i] = Float(value * env * volume)
        }
        return buffer
    }
}
