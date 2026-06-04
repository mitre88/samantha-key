import SwiftUI

struct TranslatorView: View {
    @Environment(TranslationSession.self) private var translationSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("outputLanguage") private var outputLanguageRaw = AppLanguage.english.rawValue
    let outputLanguage: AppLanguage

    @State private var startTask: Task<Void, Never>?
    private let transcriptBottomID = "transcript-bottom"

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: outputLanguageRaw) ?? outputLanguage
    }

    private var isListening: Bool {
        translationSession.state == .listening
    }

    private var stateText: LocalizedStringKey {
        switch translationSession.state {
        case .idle: "translator.state.idle"
        case .preparing: "translator.state.preparing"
        case .listening: "translator.state.listening"
        case .error: "translator.state.error"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: AppSpacing.lg) {
                            sessionStage
                            languagePicker
                            transcriptPanel

                            Color.clear
                                .frame(height: 1)
                                .id(transcriptBottomID)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xl)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: translationSession.lastTranscript) { _, _ in
                        scrollToLatest(using: proxy)
                    }
                    .onChange(of: translationSession.lastTranslation) { _, _ in
                        scrollToLatest(using: proxy)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("app.name")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("settings.title"))
                }
            }
            .onChange(of: outputLanguageRaw) { _, newValue in
                guard let language = AppLanguage(rawValue: newValue) else { return }
                AppGroupStore.selectedLanguage = language
                translationSession.updateOutputLanguage(language)
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .onDisappear { startTask?.cancel() }
        }
    }

    private var sessionStage: some View {
        VStack(spacing: AppSpacing.lg) {
            HStack(alignment: .center) {
                statusPill

                Spacer(minLength: AppSpacing.sm)

                Label(currentLanguage.displayName, systemImage: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.quietInk)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            ZStack {
                VoiceSignalField(isListening: isListening, isError: isError)
                    .frame(height: 170)

                VoiceOrb(isListening: isListening, size: 136)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            statusBlock
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(.regularMaterial)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(AppTheme.voiceTint.opacity(isListening ? 0.28 : 0.12))
                        .frame(width: 220, height: 220)
                        .blur(radius: 46)
                        .offset(x: -92, y: -92)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(AppTheme.successTint.opacity(isListening ? 0.26 : 0.10))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                        .offset(x: 70, y: 68)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
    }

    private var isError: Bool {
        if case .error = translationSession.state { return true }
        return false
    }

    private var statusBlock: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(stateText)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text("translator.subtitle")
                .font(.callout)
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
                    .padding(.top, AppSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusPill: some View {
        Label(statusLabel, systemImage: statusSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusForeground)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(statusBackground, in: Capsule(style: .continuous))
            .accessibilityHidden(true)
    }

    private var statusLabel: LocalizedStringKey {
        switch translationSession.state {
        case .idle: "translator.status.ready"
        case .preparing: "translator.status.secure"
        case .listening: "translator.status.live"
        case .error: "translator.status.error"
        }
    }

    private var statusSymbol: String {
        switch translationSession.state {
        case .idle: "checkmark.circle.fill"
        case .preparing: "lock.fill"
        case .listening: "waveform"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusForeground: Color {
        switch translationSession.state {
        case .listening: return .black
        case .error: return .red
        default: return .primary
        }
    }

    private var statusBackground: Color {
        switch translationSession.state {
        case .listening: return AppTheme.successTint
        case .error: return Color.red.opacity(0.12)
        default: return AppTheme.elevatedSurface
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "globe")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.elevatedSurface, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("settings.output_language")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .textCase(.uppercase)

                    Text(currentLanguage.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: AppSpacing.sm)

                Picker("settings.output_language", selection: $outputLanguageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }

            Divider().opacity(0.55)

            HStack(spacing: AppSpacing.sm) {
                FeatureChip(symbol: "wand.and.stars", title: "onboarding.feature.detect")
                FeatureChip(symbol: "keyboard", title: "onboarding.feature.keyboard")
                FeatureChip(symbol: "lock.shield", title: "onboarding.feature.private")
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("translator.transcript.title")
                    .font(.headline)

                Spacer()

                Text(translationSession.lastTranslation.isEmpty ? "translator.transcript.waiting" : "translator.transcript.live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(translationSession.lastTranslation.isEmpty ? AppTheme.muted : .black)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        translationSession.lastTranslation.isEmpty ? AppTheme.elevatedSurface : AppTheme.successTint,
                        in: Capsule(style: .continuous)
                    )
            }

            if translationSession.lastTranscript.isEmpty && translationSession.lastTranslation.isEmpty {
                EmptyTranscriptState()
            } else {
                if !translationSession.lastTranscript.isEmpty {
                    TranscriptBlock(
                        title: "translator.transcript.source",
                        text: translationSession.lastTranscript,
                        isPrimary: false
                    )
                }

                if !translationSession.lastTranslation.isEmpty {
                    TranscriptBlock(
                        title: "translator.transcript.translation",
                        text: translationSession.lastTranslation,
                        isPrimary: true
                    )
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppTheme.panelStroke, lineWidth: 1)
        )
        .textSelection(.enabled)
    }

    private var bottomControls: some View {
        VStack(spacing: AppSpacing.sm) {
            switch translationSession.state {
            case .listening, .preparing:
                SecondaryButton(title: "translator.stop", systemImage: "stop.fill") {
                    startTask?.cancel()
                    translationSession.stop()
                }
            default:
                DarkPrimaryButton(title: "translator.start", systemImage: "mic.fill") {
                    startTask = Task {
                        let selected = AppLanguage(rawValue: outputLanguageRaw) ?? .english
                        await translationSession.start(outputLanguage: selected)
                    }
                }
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
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard !translationSession.lastTranscript.isEmpty || !translationSession.lastTranslation.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            proxy.scrollTo(transcriptBottomID, anchor: .bottom)
        }
    }
}

struct VoiceSignalField: View {
    let isListening: Bool
    let isError: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringColor: Color {
        if isError { return .red }
        return isListening ? AppTheme.successTint : AppTheme.voiceTint
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 80, style: .continuous)
                    .strokeBorder(ringColor.opacity(0.16 - Double(index) * 0.035), lineWidth: 1)
                    .frame(width: 180 + CGFloat(index * 42), height: 92 + CGFloat(index * 22))
                    .scaleEffect(isListening && !reduceMotion ? 1.03 + CGFloat(index) * 0.025 : 1)
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 1.35 + Double(index) * 0.18).repeatForever(autoreverses: true),
                        value: isListening
                    )
            }

            HStack(spacing: AppSpacing.xs) {
                ForEach(0..<18, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(ringColor.opacity(index.isMultiple(of: 2) ? 0.30 : 0.16))
                        .frame(width: 3, height: barHeight(for: index))
                }
            }
            .opacity(isListening ? 0.9 : 0.28)
            .offset(y: 72)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [10, 16, 26, 18, 34, 22, 42, 28, 16]
        let base = pattern[index % pattern.count]
        guard isListening && !reduceMotion else { return base * 0.58 }
        return index.isMultiple(of: 3) ? base * 1.18 : base
    }
}

private struct FeatureChip: View {
    let symbol: String
    let title: LocalizedStringKey

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.quietInk)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(AppTheme.elevatedSurface, in: Capsule(style: .continuous))
    }
}

private struct EmptyTranscriptState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "quote.bubble")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.quietInk)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())

                Text("translator.transcript.empty")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.xs) {
                placeholderLine(width: 0.86)
                placeholderLine(width: 0.68)
                placeholderLine(width: 0.48)
            }
            .padding(.top, AppSpacing.xs)
            .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func placeholderLine(width: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(AppTheme.elevatedSurface)
                .frame(width: proxy.size.width * width, height: 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 8)
    }
}

private struct TranscriptBlock: View {
    let title: LocalizedStringKey
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
