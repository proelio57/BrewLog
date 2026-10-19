import AVFoundation

/// Reads the brew steps out loud with the system voice (on the device, no network).
final class VoicePrompter {
    static let shared = VoicePrompter()

    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        // The prompts are English, so use an English voice in the user's preferred region if there is one.
        let preferred = Locale.preferredLanguages.first { $0.hasPrefix("en") } ?? "en-US"
        return AVSpeechSynthesisVoice(language: preferred) ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    private init() {
        // Shares the session set up by `SoundPlayer` (plays in silent mode if that's enabled, mixes with music).
        synthesizer.usesApplicationAudioSession = true
    }

    /// Speaks after the chime has started, replacing anything still being said.
    func say(_ text: String, delay: TimeInterval = 0.35) {
        guard AppSettings.voicePrompts else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = Float(AppSettings.soundVolume)
        utterance.preUtteranceDelay = delay
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
