import SwiftUI

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let ml: CGFloat = 20
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 28
}

enum AppLayout {
    /// Comfortable reading width for single-column content on wide displays
    /// (iPhone Duo inner display, iPhone Mirroring windows).
    static let readableWidth: CGFloat = 620
    /// Available width at which paired panes sit side by side instead of stacking.
    static let twoColumnMinWidth: CGFloat = 700
    /// Lower threshold for panes that share a single card, where each column needs less room.
    static let cardColumnsMinWidth: CGFloat = 600
    /// Widest the subscription store grows, so its purchase buttons keep a comfortable length.
    static let storeMaxWidth: CGFloat = 780
}

extension View {
    /// Caps content at a readable width and centers it. No effect at regular iPhone widths.
    func readableContentWidth(_ maxWidth: CGFloat = AppLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Places two panes side by side when the available width allows it and stacks them otherwise.
/// Both panes are present in every layout, so features never depend on the device pose.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = AppSpacing.lg
    var minWidth: CGFloat = AppLayout.twoColumnMinWidth
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ColumnsLayout(
            spacing: spacing,
            minWidth: minWidth,
            allowsColumns: !dynamicTypeSize.isAccessibilitySize
        ) {
            leading
                .frame(maxWidth: .infinity, alignment: .top)
            trailing
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// Chooses columns or a stack from the proposed width inside the layout pass itself, so there is
/// no stored state, no stacked first frame and no animation inherited from a state change.
private struct ColumnsLayout: Layout {
    let spacing: CGFloat
    let minWidth: CGFloat
    let allowsColumns: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.map(\.width).max() ?? 0, height: stackedHeight(sizes.map(\.height)))
        }
        if isSideBySide(width) {
            let column = columnWidth(width, count: subviews.count)
            let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            return CGSize(width: width, height: heights.max() ?? 0)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: stackedHeight(heights))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if isSideBySide(bounds.width) {
            let column = columnWidth(bounds.width, count: subviews.count)
            for (index, subview) in subviews.enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: column, height: nil)
                )
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }

    private func isSideBySide(_ width: CGFloat) -> Bool {
        allowsColumns && width >= minWidth
    }

    private func columnWidth(_ width: CGFloat, count: Int) -> CGFloat {
        (width - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1))
    }

    private func stackedHeight(_ heights: [CGFloat]) -> CGFloat {
        heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
    }
}

enum AppTheme {
    static let pageBackground = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let elevatedSurface = Color(.tertiarySystemGroupedBackground)
    static let muted = Color.secondary
    static let successTint = Color(red: 0.46, green: 0.95, blue: 0.78)
    static let voiceTint = Color(red: 0.42, green: 0.89, blue: 1.0)
    static let keyTint = Color(red: 0.74, green: 0.82, blue: 1.0)
    static let panelStroke = Color.primary.opacity(0.08)
    static let quietInk = Color.primary.opacity(0.82)
}

struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "arrow.right")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color(white: 0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.black, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .modifier(PressFeedbackModifier(disabled: reduceMotion))
        .contentShape(Capsule(style: .continuous))
    }
}

struct GlassPanelModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(AppTheme.panelStroke, lineWidth: 1))
        }
    }
}

extension View {
    func samanthaGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(GlassPanelModifier(shape: shape, tint: tint))
    }
}

struct DarkPrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "arrow.right")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color(white: 0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.black, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .modifier(PressFeedbackModifier(disabled: reduceMotion))
        .contentShape(Capsule(style: .continuous))
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "arrow.clockwise")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .clipShape(Capsule(style: .continuous))
    }
}

struct AppSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            content
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct PressFeedbackModifier: ViewModifier {
    let disabled: Bool

    func body(content: Content) -> some View {
        if disabled {
            content
        } else {
            content.buttonStyle(ScaleOnPressButtonStyle())
        }
    }
}

private struct ScaleOnPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}
