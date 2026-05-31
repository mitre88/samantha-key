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

struct PaywallHeader: View {
    @Environment(EntitlementStore.self) private var entitlementStore

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

            SubscriptionReviewSummary(displayPrice: entitlementStore.monthlyDisplayPrice)

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

private struct SubscriptionReviewSummary: View {
    let displayPrice: String?

    var body: some View {
        AppSection {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("paywall.review.heading")
                    .font(.headline)

                ReviewSummaryRow(label: "paywall.review.title.label", value: Text("paywall.review.title.value"))
                ReviewSummaryRow(label: "paywall.review.length.label", value: Text("paywall.review.length.value"))
                ReviewSummaryRow(label: "paywall.review.price.label", value: priceText)
                ReviewSummaryRow(label: "paywall.review.trial.label", value: Text("paywall.review.trial.value"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var priceText: Text {
        if let displayPrice {
            return Text("paywall.review.price.dynamic \(displayPrice)")
        }
        return Text("paywall.review.price.loading")
    }
}

private struct ReviewSummaryRow: View {
    let label: LocalizedStringKey
    let value: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 92, alignment: .leading)

            value
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
