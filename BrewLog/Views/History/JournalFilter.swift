import Foundation

/// The journal's filter chips: Filter or Espresso, brews still to review, one bean, one recipe.
/// Kept apart from the view so it can be tested without SwiftData.
struct JournalFilter: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case all, filter, espresso
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .filter: return "Filter"
            case .espresso: return "Espresso"
            }
        }
    }

    var kind: Kind = .all
    var toReview = false
    /// A bean's display name ("Name · Roaster"); nil = any.
    var bean: String?
    var recipe: String?

    var isActive: Bool { kind != .all || toReview || bean != nil || recipe != nil }

    func matches(isEspresso: Bool, isReviewed: Bool, bean beanName: String?, recipe recipeName: String) -> Bool {
        switch kind {
        case .all: break
        case .filter: if isEspresso { return false }
        case .espresso: if !isEspresso { return false }
        }
        if toReview, isReviewed { return false }
        if let bean, bean != beanName { return false }
        if let recipe, recipe != recipeName { return false }
        return true
    }

    /// The distinct non-empty names, most frequent first (ties alphabetical), for the bean and recipe menus.
    static func options(_ names: [String?]) -> [String] {
        var counts: [String: Int] = [:]
        for case let name? in names where !name.isEmpty { counts[name, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
