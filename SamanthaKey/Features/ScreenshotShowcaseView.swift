#if DEBUG
import SwiftUI

enum ScreenshotScene {
    static var requestedScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-screenshotMode"),
              let index = args.firstIndex(of: "-screenshotScreen"),
              args.indices.contains(index + 1)
        else { return nil }
        return args[index + 1]
    }
}

struct ScreenshotShowcaseView: View {
    let screen: String

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case "keyboard":
                    KeyboardMarketingScene()
                case "handoff":
                    HandoffMarketingScene()
                case "setup":
                    KeyboardSetupView()
                case "paywall":
                    PaywallMarketingScene()
                default:
                    LiveTranslationMarketingScene()
                }
            }
        }
        .tint(.primary)
    }
}

private struct LiveTranslationMarketingScene: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                ScreenshotNavTitle()
                VoiceHeroCard(state: "Live translation", language: "English", isListening: true)

                AppSection {
                    TranscriptPreview(
                        title: "Detected speech",
                        text: "Hola, llego en diez minutos. ¿Puedes guardar una mesa cerca de la ventana?",
                        isPrimary: false
                    )
                    TranscriptPreview(
                        title: "Translated text",
                        text: "Hi, I’ll arrive in ten minutes. Can you save a table near the window?",
                        isPrimary: true
                    )
                }

                Spacer(minLength: 0)

                DarkPrimaryButton(title: "Speak to translate", systemImage: "mic.fill") {}
                    .padding(.bottom, AppSpacing.sm)
            }
            .padding(AppSpacing.lg)
        }
    }
}

private struct HandoffMarketingScene: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                ScreenshotNavTitle()
                VoiceHeroCard(state: "Recording for keyboard", language: "Portuguese", isListening: true)

                AppSection {
                    FeatureRow(
                        icon: "keyboard",
                        title: "Return to any text field",
                        detail: "The translated text is prepared for your keyboard, ready to insert."
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "No saved transcript",
                        detail: "Audio is processed live for translation and is not stored by Samantha Key."
                    )
                }

                Spacer(minLength: 0)

                SecondaryButton(title: "Stop recording", systemImage: "stop.fill") {}
                    .padding(.bottom, AppSpacing.sm)
            }
            .padding(AppSpacing.lg)
        }
    }
}

private struct KeyboardMarketingScene: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(red: 0.89, green: 0.97, blue: 1.0),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                ScreenshotNavTitle()

                VStack(spacing: AppSpacing.md) {
                    Label("Samantha Key", systemImage: "sparkle.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.quietInk)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.thinMaterial, in: Capsule(style: .continuous))

                    Text("Speak once. Insert translated text anywhere.")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)

                    KeyboardSurfacePreview()
                }
                .padding(AppSpacing.lg)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
                )

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.lg)
        }
    }
}

private struct PaywallMarketingScene: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                ScreenshotNavTitle()
                PaywallHeader()

                AppSection {
                    PaywallLine(icon: "checkmark.seal.fill", text: "3 days free, then MXN $149/month")
                    PaywallLine(icon: "apple.logo", text: "Subscription managed securely by Apple")
                    PaywallLine(icon: "arrow.clockwise.circle.fill", text: "Cancel anytime in App Store settings")
                }

                Spacer(minLength: 0)

                PrimaryButton(title: "Start free trial", systemImage: "sparkles") {}
                    .padding(.bottom, AppSpacing.sm)
            }
            .padding(AppSpacing.lg)
        }
    }
}

private struct ScreenshotNavTitle: View {
    var body: some View {
        Text("Samantha Key")
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xs)
    }
}

private struct VoiceHeroCard: View {
    let state: String
    let language: String
    let isListening: Bool

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            HStack {
                Label(state, systemImage: isListening ? "waveform" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isListening ? .black : .primary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(isListening ? AppTheme.successTint : AppTheme.elevatedSurface, in: Capsule(style: .continuous))

                Spacer()

                Label(language, systemImage: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.quietInk)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
            }

            ZStack {
                VoiceSignalField(isListening: isListening, isError: false)
                    .frame(height: 172)
                VoiceOrb(isListening: isListening, size: 136)
            }

            VStack(spacing: AppSpacing.xs) {
                Text(isListening ? "Listening in real time" : "Ready for voice")
                    .font(.title3.bold())
                Text("Speak naturally. Samantha prepares translated text for the language you choose.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct TranscriptPreview: View {
    let title: String
    let text: String
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Capsule(style: .continuous)
                .fill(isPrimary ? AppTheme.successTint : AppTheme.voiceTint.opacity(0.65))
                .frame(width: 4)
                .padding(.vertical, AppSpacing.xxs)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .textCase(.uppercase)

                Text(text)
                    .font(isPrimary ? .body.weight(.semibold) : .callout)
                    .foregroundStyle(isPrimary ? .primary : AppTheme.muted)
                    .lineSpacing(3)
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(isPrimary ? AppTheme.successTint.opacity(0.20) : AppTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .strokeBorder(isPrimary ? AppTheme.successTint.opacity(0.24) : AppTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct KeyboardSurfacePreview: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .frame(width: 44, height: 32)
                    .background(Color.white.opacity(0.62), in: Capsule(style: .continuous))
                Text("Samantha Key")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("English")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.62), in: Capsule(style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(AppTheme.successTint)
                        .frame(width: 7, height: 7)
                    Text("Translation ready")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Insert")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.successTint, in: Capsule())
                }

                Text("I’ll meet you by the stadium entrance after the match.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            }
            .padding(12)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 10) {
                Label("Speak to translate", systemImage: "mic.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black, in: Capsule(style: .continuous))

                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 54, height: 54)
                    .background(Color.white.opacity(0.72), in: Circle())
            }

            HStack(spacing: 8) {
                Text("delete")
                Text("space").frame(maxWidth: .infinity)
                Text("return")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.62))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
#endif
