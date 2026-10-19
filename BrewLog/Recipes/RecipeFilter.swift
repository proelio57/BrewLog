import Foundation

/// Filters the recipe lists by brewer type, so you don't scroll past recipes for gear you don't have.
enum RecipeFilter {
    /// Whether a recipe fits a brewer of this type. "Any pour-over" recipes fit every pour-over brewer.
    static func matches(_ recipe: Recipe, method: BrewMethod?) -> Bool {
        guard let method else { return true }
        if recipe.method == method { return true }
        return !method.isEspresso && recipe.method == .universal
    }

    struct Section: Equatable {
        var title: String
        var recipes: [Recipe]
    }

    /// "My recipes" first, then the built-in recipes grouped by method; the filtered method's group comes first.
    static func sections(custom: [Recipe], presets: [Recipe], method: BrewMethod?) -> [Section] {
        var result: [Section] = []
        let mine = custom.filter { matches($0, method: method) }
        if !mine.isEmpty { result.append(Section(title: "My recipes", recipes: mine)) }
        var order = BrewMethod.allCases
        if let method, let index = order.firstIndex(of: method) { order.insert(order.remove(at: index), at: 0) }
        for group in order {
            let recipes = presets.filter { $0.method == group && matches($0, method: method) }
            if !recipes.isEmpty { result.append(Section(title: group.displayName, recipes: recipes)) }
        }
        return result
    }

    /// The methods that have recipes, for the filter chips.
    static func methods(in recipes: [Recipe]) -> [BrewMethod] {
        let present = Set(recipes.map(\.method))
        // "Any pour-over" isn't a brewer, its recipes show up under every pour-over filter.
        return BrewMethod.allCases.filter { present.contains($0) && $0 != .universal }
    }
}

extension Recipe {
    /// The valve position a step switches to (Hario Switch and similar), nil when the valve stays as it is.
    /// The position at the start of the brew isn't a change.
    func valveChange(at index: Int) -> ValveState? {
        guard steps.indices.contains(index), index > 0, steps[index].time > 0,
              let target = Self.valve(of: steps[index]) else { return nil }
        let previous = steps[..<index].reversed().lazy.compactMap(Self.valve(of:)).first
        return previous == target ? nil : target
    }

    private static func valve(of step: RecipeStep) -> ValveState? {
        switch step.kind {
        case .closeValve: return .closed
        case .openValve: return .open
        default: return step.valve
        }
    }
}
