import AVFoundation
import UIKit

enum BrewCue: CaseIterable {
    /// Short, high, soft "ding" just before the pour target is reached.
    case target
    /// Gentle two-note chime: time for the next step.
    case nextStep
    /// Calm three-note phrase: target brew time reached.
    case finish
    /// Very soft tick for the 3-2-1 countdown.
    case tick
}

/// Synthesizes soft bell-like cues at runtime (no audio assets needed) and plays them with low latency.
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var buffers: [BrewCue: AVAudioPCMBuffer] = [:]
    private var isConfigured = false

    private init() {}

    func prepare() {
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = AppSettings.silentModeSound ? .playback : .ambient
        try? session.setCategory(category, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        if !isConfigured {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConfigured = true
        }
        if buffers.isEmpty { renderAll() }
        if !engine.isRunning {
            do { try engine.start() } catch { print("Audio engine failed: \(error)") }
        }
    }

    /// Stops the audio engine so the app can suspend in the background. `play` starts it again when needed.
    func stop() {
        guard engine.isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Plays the sound (if enabled) and the matching haptic (if enabled).
    func cue(_ cue: BrewCue) {
        if AppSettings.soundEnabled { play(cue) }
        if AppSettings.hapticsEnabled { Haptics.play(cue) }
    }

    func play(_ cue: BrewCue) {
        if !engine.isRunning { prepare() }
        guard let buffer = buffers[cue] else { return }
        player.volume = Float(AppSettings.soundVolume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    private struct Note {
        let frequency: Double
        let delay: Double
        let gain: Double
    }

    private func renderAll() {
        // E6 – single, short, soft ping
        buffers[.target] = render(notes: [Note(frequency: 1318.5, delay: 0, gain: 0.9)], decay: 9, duration: 0.55)
        // A5 → E6 rising chime
        buffers[.nextStep] = render(notes: [Note(frequency: 880, delay: 0, gain: 0.8),
                                            Note(frequency: 1318.5, delay: 0.13, gain: 0.7)],
                                    decay: 5, duration: 1.3)
        // C6 → G5 → E5 calm, descending
        buffers[.finish] = render(notes: [Note(frequency: 1046.5, delay: 0, gain: 0.7),
                                          Note(frequency: 784, delay: 0.2, gain: 0.7),
                                          Note(frequency: 659.3, delay: 0.4, gain: 0.8)],
                                  decay: 3.5, duration: 2.0)
        buffers[.tick] = render(notes: [Note(frequency: 1760, delay: 0, gain: 0.35)], decay: 35, duration: 0.12)
    }

    /// Bell/marimba-like tone: a fundamental with quickly decaying partials, a soft attack and an exponential decay.
    private func render(notes: [Note], decay: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let fadeOutFrames = Int(0.03 * sampleRate)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in notes where t >= note.delay {
                let lt = t - note.delay
                let attack = min(1, lt / 0.008)
                let envelope = attack * exp(-lt * decay)
                let w = 2 * Double.pi * note.frequency * lt
                let partials = sin(w)
                    + 0.30 * exp(-lt * decay * 0.8) * sin(2 * w)
                    + 0.10 * exp(-lt * decay * 1.6) * sin(3.01 * w)
                sample += note.gain * envelope * partials
            }
            var value = sample * 0.32
            let remaining = Int(frameCount) - i
            if remaining < fadeOutFrames { value *= Double(remaining) / Double(fadeOutFrames) }
            channel[i] = Float(value)
        }
        return buffer
    }
}

enum Haptics {
    static func play(_ cue: BrewCue) {
        switch cue {
        case .target:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
        case .nextStep:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .finish:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .tick:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        }
    }

    static func tap() {
        guard AppSettings.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
