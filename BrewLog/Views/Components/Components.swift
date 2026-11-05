import SwiftUI

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Stat pill

struct StatView: View {
    let value: String
    let label: String
    var symbol: String?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) }
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Taste profile

struct TasteProfileView: View {
    let profile: TasteProfile

    var body: some View {
        VStack(spacing: 8) {
            row("Acidity", profile.acidity, .yellow)
            row("Sweetness", profile.sweetness, .orange)
            row("Body", profile.body, .brown)
            row("Clarity", profile.clarity, .teal)
        }
    }

    private func row(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Capsule()
                        .fill(index <= value ? color.gradient : Color(.tertiarySystemFill).gradient)
                        .frame(height: 8)
                }
            }
        }
    }
}

// MARK: - Stars

struct StarRating: View {
    @Binding var rating: Int
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    rating = rating == index ? 0 : index
                    Haptics.tap()
                } label: {
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(index <= rating ? Color.orange : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StarsLabel: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(index <= rating ? Color.orange : Color.secondary.opacity(0.3))
            }
        }
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var symbol: String?
    var isSelected: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? tint.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 1.5))
        .foregroundStyle(isSelected ? tint : .primary)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Menu picker row

struct PickerOption: Identifiable, Hashable {
    let id: UUID
    let name: String
}

/// A compact "Title ……… Selection ⌃⌄" row. Long names truncate to one line instead of wrapping.
struct MenuPickerRow: View {
    let title: String
    let symbol: String
    let options: [PickerOption]
    @Binding var selection: UUID?
    var noneLabel = "None"

    private var selectedName: String {
        options.first { $0.id == selection }?.name ?? noneLabel
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            Menu {
                Picker(title, selection: $selection) {
                    Text(noneLabel).tag(UUID?.none)
                    ForEach(options) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .accessibilityIdentifier("picker.\(title)")
        }
        .font(.subheadline)
    }
}

// MARK: - Method badge

struct MethodBadge: View {
    let method: BrewMethod
    var body: some View {
        Label(method.displayName, systemImage: method.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

extension FindingLevel {
    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    var color: Color {
        switch self {
        case .good: return .green
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

extension Double {
    /// Avoids a flickering "-0.0" from scale noise around zero.
    var noiseFree: Double { abs(self) < 0.05 ? 0 : self }
    var grams: String { String(format: "%.0f g", noiseFree) }
    var grams1: String { String(format: "%.1f g", noiseFree) }
    /// Live scale readout without unit, e.g. "123.4".
    var scaleReadout: String { String(format: "%.1f", noiseFree) }
}

/// A small capsule switch with a thumb that slides (tap or drag), e.g. Filter | Espresso, Journal | Stats.
/// All options are as wide as the widest, so the thumb keeps its size when it moves.
/// The thumb slides first and the selection follows when it has arrived, so the content swap doesn't cut
/// the animation short.
struct CapsuleOption<Value: Hashable> {
    let value: Value
    let title: String
    let symbol: String
}

struct CapsuleSwitch<Value: Hashable>: View {
    let options: [CapsuleOption<Value>]
    @Binding var selection: Value
    /// The option the thumb is on; ahead of `selection` while the thumb slides.
    @State private var shown: Value?
    /// Thumb position (leading edge) while the finger drags it.
    @State private var dragX: CGFloat?
    @State private var commit: DispatchWorkItem?

    private static var slide: Animation { .spring(response: 0.3, dampingFraction: 0.86) }
    private static var inset: CGFloat { 3 }
    private var current: Value { shown ?? selection }
    private var currentIndex: Int { options.firstIndex { $0.value == current } ?? 0 }

    var body: some View {
        EqualWidthRow {
            ForEach(options, id: \.value) { option in label(option) }
        }
        // Sized in the same layout pass as the labels, so the thumb is right from the first frame.
        .background {
            GeometryReader { proxy in thumb(segment: segmentWidth(proxy.size.width)) }
        }
        .padding(Self.inset)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Capsule())
                    .gesture(drag(segment: segmentWidth(proxy.size.width - 2 * Self.inset)))
            }
        }
        .fixedSize()
        .onChange(of: selection) { _, new in
            // Changed from outside (not by a pending pick): follow it.
            if commit == nil { shown = new }
        }
        .onDisappear {
            commit?.cancel()
            commit = nil
        }
    }

    private func segmentWidth(_ total: CGFloat) -> CGFloat { total / CGFloat(max(options.count, 1)) }

    private func label(_ option: CapsuleOption<Value>) -> some View {
        let selected = option.value == current
        return Label(option.title, systemImage: option.symbol)
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .animation(.easeOut(duration: 0.18), value: selected)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { pick(option.value) }
    }

    /// The accent capsule under the selected option; follows the finger while dragging.
    private func thumb(segment: CGFloat) -> some View {
        let x = dragX ?? CGFloat(currentIndex) * segment
        return Capsule()
            .fill(Color.accentColor.gradient)
            .frame(width: segment)
            .offset(x: x)
            .animation(dragX == nil ? Self.slide : .interactiveSpring(response: 0.15), value: x)
    }

    private func drag(segment: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A tap shouldn't make the thumb jump to the finger first: only follow a real drag.
                guard segment > 0, dragX != nil || abs(value.translation.width) > 6 else { return }
                let total = segment * CGFloat(options.count)
                dragX = min(max(value.location.x - segment / 2, 0), total - segment)
            }
            .onEnded { value in
                guard segment > 0 else { return }
                let index = min(max(Int(value.location.x / segment), 0), options.count - 1)
                dragX = nil
                pick(options[index].value)
            }
    }

    private func pick(_ value: Value) {
        // Already there or on its way (a drag released on the same option just snaps back).
        guard value != current else { return }
        commit?.cancel()
        commit = nil
        withAnimation(Self.slide) { shown = value }
        Haptics.tap()
        // Back to the screen that is showing: nothing to swap.
        guard value != selection else { return }
        // Let the thumb arrive before the content behind it changes. A newer pick cancels this one,
        // so quick taps back and forth don't swap the screen twice.
        let work = DispatchWorkItem {
            commit = nil
            selection = value
        }
        commit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
    }
}

/// Lays its children out side by side, each as wide as the widest.
private struct EqualWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.map(\.width).max() ?? 0
        return CGSize(width: width * CGFloat(subviews.count), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + width * (CGFloat(index) + 0.5), y: bounds.midY),
                          anchor: .center, proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
