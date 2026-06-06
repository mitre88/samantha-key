import SwiftUI

struct RootView: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(TranslationSession.self) private var translationSession
    @Environment(KeyboardHandoffCoordinator.self) private var keyboardHandoff
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
            } else if keyboardHandoff.isActive {
                KeyboardHandoffRecordingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
            if keyboardHandoff.isActive {
                KeyboardHandoffRecordingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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

private struct KeyboardHandoffRecordingView: View {
    @Environment(TranslationSession.self) private var translationSession
    @Environment(KeyboardHandoffCoordinator.self) private var keyboardHandoff

    private var isListening: Bool {
        translationSession.state == .listening
    }

    private var isError: Bool {
        if case .error = translationSession.state { return true }
        return false
    }

    private var stateTitle: String {
        switch translationSession.state {
        case .idle:
            "Ready for keyboard"
        case .preparing:
            "Preparing translation"
        case .listening:
            "Recording for keyboard"
        case .error:
            "Needs attention"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                VStack(spacing: AppSpacing.lg) {
                    Spacer(minLength: AppSpacing.md)

                    VStack(spacing: AppSpacing.lg) {
                        Label(keyboardHandoff.outputLanguage.displayName, systemImage: "keyboard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.quietInk)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(.thinMaterial, in: Capsule(style: .continuous))

                        ZStack {
                            VoiceSignalField(isListening: isListening, isError: isError)
                                .frame(height: 172)
                            VoiceOrb(isListening: isListening, size: 138)
                        }
                        .accessibilityHidden(true)

                        VStack(spacing: AppSpacing.sm) {
                            Text(stateTitle)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)

                            Text(statusText)
                                .font(.body)
                                .foregroundStyle(AppTheme.muted)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)

                            if !translationSession.diagnosticMessage.isEmpty {
                                Text(translationSession.diagnosticMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.quietInk)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                            }
                        }

                        if !translationSession.lastTranslation.isEmpty {
                            KeyboardTranslationPreview(text: translationSession.lastTranslation)
                        }

                        if case .error(let message) = translationSession.state {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(AppSpacing.sm)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        }
                    }
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
                    )

                    Spacer(minLength: AppSpacing.md)

                    SecondaryButton(title: "Stop and send text", systemImage: "paperplane.fill") {
                        keyboardHandoff.stop()
                    }
                }
                .padding(AppSpacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Samantha Key")
                        .font(.headline.weight(.semibold))
                }
            }
        }
    }

    private var statusText: String {
        if isListening {
            return "Speak now. Tap Stop and send text, then return to your original field. The keyboard will insert the translation automatically."
        }
        if case .error = translationSession.state {
            return "Fix the issue below, then return to the keyboard and try again."
        }
        return keyboardHandoff.message
    }
}

private struct KeyboardTranslationPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("translator.transcript.translation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .textCase(.uppercase)

            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.successTint.opacity(0.20), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .strokeBorder(AppTheme.successTint.opacity(0.24), lineWidth: 1)
        )
    }
}
