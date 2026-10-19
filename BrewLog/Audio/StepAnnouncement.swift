import Foundation

/// What the voice prompts say during a brew (see `VoicePrompter`), so you don't need to look at the screen while pouring.
enum StepAnnouncement {
    /// Seconds before a step when it is announced ahead.
    static let leadTime = 5.0

    /// Spoken at the start of a step, e.g. "Pour to 150 grams."
    static func text(for step: RecipeStep) -> String {
        var sentence: String
        switch step.kind {
        case .bloom, .pour, .extract:
            if let target = step.target {
                let verb = step.kind == .bloom ? "Bloom to" : (step.kind == .extract ? "Extract to" : "Pour to")
                sentence = "\(verb) \(grams(target))."
            } else {
                sentence = "\(step.kind.title)."
            }
        case .swirl: sentence = "Swirl gently."
        case .stir: sentence = "Stir."
        case .closeValve: sentence = "Close the valve."
        case .openValve: sentence = "Open the valve."
        case .remove: sentence = "Remove the dripper."
        case .preinfuse: sentence = "Pre-infusion."
        }
        if let note = spokenNote(step.note) { sentence += " " + note }
        return sentence
    }

    /// Spoken a few seconds before a step, e.g. "Next, pour to 250 grams."
    static func preview(for step: RecipeStep) -> String {
        let action = text(for: RecipeStep(kind: step.kind, time: step.time, target: step.target, valve: step.valve, note: nil))
        let lowered = action.prefix(1).lowercased() + action.dropFirst().dropLast()
        return "Next, \(lowered)."
    }

    static let finished = "Brew time reached."

    static func grams(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded == 1 ? "1 gram" : "\(rounded) grams"
    }

    /// Short notes are read out, long ones would run into the next step.
    private static func spokenNote(_ note: String?) -> String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty, note.count <= 80 else { return nil }
        return note.hasSuffix(".") || note.hasSuffix("!") ? note : note + "."
    }
}
