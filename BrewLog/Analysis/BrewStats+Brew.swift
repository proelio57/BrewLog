import Foundation

extension Brew {
    /// This brew as input for `BrewStats`. Espresso numbers (first drops, pressure) only for espresso brews.
    var statsEntry: BrewStats.Entry {
        let espresso = isEspresso
        let pressure = espresso ? EspressoAnalyzer.pressureSummary(machineSamples) : nil
        return BrewStats.Entry(
            date: date,
            espresso: espresso,
            rating: rating,
            beanID: bean?.id,
            beanName: bean?.name ?? BrewStats.noBeanName,
            recipeName: recipeName.isEmpty ? (recipe?.name ?? "") : recipeName,
            dose: dose,
            yield: finalWeight,
            time: totalTime,
            targetTime: recipe?.targetTime ?? 0,
            grind: grindDisplay,
            extractionYield: extractionYield,
            firstDrops: espresso ? EspressoAnalyzer.firstDrops(samples) : nil,
            peakPressure: pressure?.peak,
            suddenDrop: pressure?.suddenDrop
        )
    }
}
