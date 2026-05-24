import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    private let privacyURL = URL(string: "https://samantha-key-support.vercel.app/#privacy")!
    private let termsURL = URL(string: "https://samantha-key-support.vercel.app/#terms")!

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                SubscriptionStoreView(productIDs: [EntitlementStore.monthlyProductID]) {
                    PaywallHeader()
                }
                .subscriptionStoreControlStyle(.buttons)
                .subscriptionStoreButtonLabel(.multiline)
                .storeButton(.visible, for: .restorePurchases)
            }
            .navigationTitle("app.name")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PaywallFooter(
                    isLoading: entitlementStore.isLoading,
                    errorMessage: entitlementStore.errorMessage,
                    privacyURL: privacyURL,
                    termsURL: termsURL
                )
            }
        }
        .task { await entitlementStore.refresh() }
    }
}

private struct PaywallHeader: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Label("paywall.native_badge", systemImage: "apple.logo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.quietInk)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(.thinMaterial, in: Capsule(style: .continuous))

            ZStack {
                Circle()
                    .fill(AppTheme.successTint.opacity(0.16))
                    .frame(width: 180, height: 180)
                    .blur(radius: 34)

                VoiceOrb(isListening: false, size: 106)
            }
            .frame(height: 126)
            .accessibilityHidden(true)

            VStack(spacing: AppSpacing.sm) {
                Text("paywall.title")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text("paywall.subtitle")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppSection {
                PaywallLine(icon: "checkmark.seal.fill", text: "paywall.line.trial")
                PaywallLine(icon: "speaker.wave.3.fill", text: "paywall.line.realtime")
                PaywallLine(icon: "lock.fill", text: "paywall.line.privacy")
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }
}

struct PaywallLine: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PaywallFooter: View {
    let isLoading: Bool
    let errorMessage: String?
    let privacyURL: URL
    let termsURL: URL

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            if isLoading {
                ProgressView("paywall.loading")
                    .font(.caption)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("paywall.apple_checkout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("paywall.disclaimer")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.md) {
                Link("settings.privacy.link", destination: privacyURL)
                Link("settings.terms.link", destination: termsURL)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
