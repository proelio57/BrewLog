import Foundation
import SwiftData
import WidgetKit

/// Keeps the Home and Lock Screen widgets up to date (see `WidgetSnapshot`).
enum WidgetSync {
    /// Called when the app goes to the background and after a brew is saved.
    @MainActor
    static func update(context: ModelContext, selectedBeanID: UUID?) {
        var last = FetchDescriptor<Brew>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        last.fetchLimit = 1
        let brew = (try? context.fetch(last))?.first

        // The bean selected on the Brew tab, else the one of the last brew.
        var bean = brew?.bean
        if let selectedBeanID {
            let id = selectedBeanID
            var selected = FetchDescriptor<Bean>(predicate: #Predicate { $0.id == id })
            selected.fetchLimit = 1
            if let found = (try? context.fetch(selected))?.first, !found.isArchived { bean = found }
        }

        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let recent = FetchDescriptor<Brew>(predicate: #Predicate { $0.date >= weekAgo })
        let snapshot = WidgetSnapshot(
            lastBrew: brew.map {
                WidgetSnapshot.LastBrew(recipeName: $0.recipeName, date: $0.date, rating: $0.rating,
                                        grind: $0.grindDisplay, ratio: $0.ratio)
            },
            bean: bean.map {
                WidgetSnapshot.BeanInfo(name: $0.name, roaster: $0.roaster, roastDate: $0.roastDate,
                                        remaining: $0.remaining, bagWeight: $0.bagWeight)
            },
            next: bean.flatMap(nextBrew),
            brewsThisWeek: (try? context.fetchCount(recent)) ?? 0)

        // Widget reloads are budgeted by iOS: only when something changed.
        if var previous = SharedStore.load() {
            previous.updated = snapshot.updated
            if previous == snapshot { return }
        }
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The bean's last brew: its recipe and the grind to use next (the review's suggestion, else the same grind).
    private static func nextBrew(for bean: Bean) -> WidgetSnapshot.NextBrew? {
        guard let last = (bean.brews ?? []).max(by: { $0.date < $1.date }) else { return nil }
        var grind = last.grindDisplay
        if let suggested = last.suggestedGrind { grind = (last.grinderSpec ?? GrinderSpec()).format(suggested) }
        return WidgetSnapshot.NextBrew(recipeName: last.recipeName, grind: grind)
    }
}
