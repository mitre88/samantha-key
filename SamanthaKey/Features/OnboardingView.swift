import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        HeaderBlock()
                        FeatureList()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "onboarding.continue", systemImage: "arrow.right", action: onContinue)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.sm)
                    .background(.regularMaterial)
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct HeaderBlock: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(AppTheme.voiceTint.opacity(0.16))
                    .frame(width: 190, height: 190)
                    .blur(radius: 34)

                VoiceOrb(isListening: true, size: 112)
            }
            .frame(height: 130)
            .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text("app.tagline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.quietInk)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.thinMaterial, in: Capsule(style: .continuous))

                Text("onboarding.title")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.body")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct FeatureList: View {
    var body: some View {
        AppSection {
            FeatureRow(
                icon: "sparkles",
                title: "onboarding.feature.detect",
                detail: "onboarding.feature.detect.body"
            )

            FeatureRow(
                icon: "speaker.wave.2.fill",
                title: "onboarding.feature.speak",
                detail: "onboarding.feature.speak.body"
            )

            FeatureRow(
                icon: "keyboard",
                title: "onboarding.feature.keyboard",
                detail: "onboarding.feature.keyboard.body"
            )

            FeatureRow(
                icon: "lock.shield.fill",
                title: "onboarding.feature.private",
                detail: "onboarding.feature.private.body"
            )
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
