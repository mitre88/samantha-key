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
