import SwiftUI

extension Color {
    /// Signature coral accent (#DD5633).
    static let brand = Color(red: 221.0 / 255.0, green: 86.0 / 255.0, blue: 51.0 / 255.0)
}

/// 22pt continuous rounded card on the secondary grouped background — the primary surface.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func card(radius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

/// A small-caps section label (e.g. "DISTANCE", "GOAL").
struct CapsLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

/// Equal-width accent-filled segmented chips (the Distance/Time toggle look).
struct SegmentedChips<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var disabled = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let selected = opt.0 == selection
                Button { selection = opt.0 } label: {
                    Text(opt.1)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? Color.brand : .primary)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Color.brand.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.brand.opacity(0.85) : .clear, lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// Horizontally scrolling capsule chips (preset pickers — 5K, 10K, 30 min…).
struct ChipScroller<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var disabled = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    let selected = opt.0 == selection
                    Button { selection = opt.0 } label: {
                        Text(opt.1)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .foregroundStyle(selected ? Color.brand : .primary)
                    }
                    .background(
                        Capsule().fill(selected ? Color.brand.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule().strokeBorder(selected ? Color.brand.opacity(0.85) : .clear, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 1)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}
