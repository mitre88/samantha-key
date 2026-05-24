import SwiftUI

struct RootView: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(TranslationSession.self) private var translationSession
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("outputLanguage") private var outputLanguageRaw = AppLanguage.english.rawValue
    @State private var showSplash = true

    private var outputLanguage: AppLanguage {
        AppLanguage(rawValue: outputLanguageRaw) ?? .english
    }

    var body: some View {
        ZStack {
#if DEBUG
            if let screenshotScreen = ScreenshotScene.requestedScreen {
                ScreenshotShowcaseView(screen: screenshotScreen)
                    .transition(.opacity)
            } else if showSplash {
                SplashView()
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    AppGroupStore.selectedLanguage = outputLanguage
                }
            } else if !entitlementStore.hasAccess {
                PaywallView()
            } else {
                TranslatorView(outputLanguage: outputLanguage)
            }
#else
            if showSplash {
                SplashView()
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    AppGroupStore.selectedLanguage = outputLanguage
                }
            } else if !entitlementStore.hasAccess {
                PaywallView()
            } else {
                TranslatorView(outputLanguage: outputLanguage)
            }
#endif
        }
        .animation(.smooth(duration: 0.35), value: showSplash)
        .task {
#if DEBUG
            guard ScreenshotScene.requestedScreen == nil else { return }
#endif
            try? await Task.sleep(for: .seconds(1.5))
            showSplash = false
        }
    }
}
