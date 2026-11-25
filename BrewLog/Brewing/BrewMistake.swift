import Foundation

/// A brew that was probably started or stopped by mistake: very short, or hardly any weight in the cup.
/// The rating screen then highlights "Discard brew".
enum BrewMistake: Equatable {
    case tooShort
    case tooLittle

    /// Shorter than this is no shot (espresso).
    static let minEspressoSeconds = 8.0
    /// Shorter than this is no pour-over.
    static let minPourOverSeconds = 30.0

    /// What looks wrong about the brew, or nil when it looks like a real one. The weight only counts with a scale.
    static func check(isEspresso: Bool, usedScale: Bool, totalTime: Double, finalWeight: Double, targetWater: Double) -> BrewMistake? {
        if totalTime < (isEspresso ? minEspressoSeconds : minPourOverSeconds) { return .tooShort }
        if usedScale, finalWeight < max(2, targetWater * 0.15) { return .tooLittle }
        return nil
    }
}
