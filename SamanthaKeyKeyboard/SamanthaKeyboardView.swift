import SwiftUI

@MainActor
protocol SamanthaKeyboardActionDelegate: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func insertSpace()
    func insertReturn()
    func switchToNextKeyboard()
    func clearDraft()
    func openRecorder()
}

struct SamanthaKeyboardView: View {
    weak var delegate: (any SamanthaKeyboardActionDelegate)?
    let needsInputModeSwitchKey: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedLanguage = AppGroupStore.selectedLanguage
    @State private var pendingText = AppGroupStore.pendingText
    @State private var status = AppGroupStore.status
    @State private var sessionID = AppGroupStore.currentSessionID
    @State private var localPendingText = ""
    @State private var localStatus: HandoffStatus?
    @State private var localSessionID = ""
    @State private var localFeedbackDate = Date.distantPast
    @State private var lastInsertedText = ""
    @State private var lastInsertedSessionID = ""
    @State private var refreshDate = Date()

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    private var isDark: Bool { colorScheme == .dark }
    private var effectiveStatus: HandoffStatus { localStatus ?? status }
    private var effectivePendingText: String { localStatus == nil ? pendingText : localPendingText }
    private var effectiveSessionID: String { localStatus == nil ? sessionID : localSessionID }
    private var canInsert: Bool {
        !effectivePendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveStatus != .error
    }

    var body: some View {
        ZStack {
            keyboardBackground

            VStack(spacing: 8) {
                topBar
                draftPanel
                controlRow
                utilityRow
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 7)
        }
        .onReceive(timer) { _ in refreshState() }
        .onReceive(NotificationCenter.default.publisher(for: KeyboardLocalFeedback.notificationName)) { notification in
            applyLocalFeedback(notification)
        }
        .onChange(of: selectedLanguage) { _, newValue in
            AppGroupStore.selectedLanguage = newValue
        }
    }

    private var keyboardBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.03 : 0.50),
                        Color(red: 0.72, green: 0.92, blue: 1.0).opacity(isDark ? 0.08 : 0.18),
                        Color.black.opacity(isDark ? 0.18 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            if needsInputModeSwitchKey {
                compactIconButton(systemImage: "globe") { delegate?.switchToNextKeyboard() }
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                Text("Samantha Key")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary.opacity(0.86))
            .layoutPriority(1)

            Spacer(minLength: 4)

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button(language.plainName) {
                        selectedLanguage = language
                        AppGroupStore.selectedLanguage = language
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selectedLanguage.keyboardBadge)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.primary)
                .frame(minWidth: 58)
                .frame(height: 34)
                .background(panelBackground, in: Capsule(style: .continuous))
            }
        }
    }

    private var draftPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                if canInsert {
                    Button { insertDraft() } label: {
                        Label("Insert", systemImage: "arrow.down.doc.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 26)
                            .background(Color(red: 0.60, green: 0.96, blue: 0.79), in: Capsule())
                    }
                    .accessibilityLabel("Insert translation")
                }
            }

            Text(displayText)
                .font(.system(size: 14, weight: canInsert ? .semibold : .regular, design: .rounded))
                .foregroundStyle(effectiveStatus == .error ? .red : (canInsert ? .primary : .secondary))
                .lineLimit(effectiveStatus == .error ? 3 : 2)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                .contentTransition(.opacity)
        }
        .padding(10)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.14 : 0.08), lineWidth: 1)
        )
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Button {
                beginLocalOpenFeedback()
                delegate?.openRecorder()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: effectiveStatus == .recording ? "waveform" : "mic.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(effectiveStatus == .recording ? "Listening in app" : "Speak to translate")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(Color(white: 0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.black, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                delegate?.clearDraft()
                refreshState()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 50, height: 50)
                    .background(panelBackground, in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var utilityRow: some View {
        HStack(spacing: 8) {
            keyButton(systemImage: "delete.backward") { delegate?.deleteBackward() }
            keyButton(title: "space") { delegate?.insertSpace() }
            keyButton(systemImage: "return.left") { delegate?.insertReturn() }
        }
    }

    private var panelBackground: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.72)
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .ready: Color(red: 0.42, green: 0.95, blue: 0.68)
        case .recording, .requested: Color(red: 0.42, green: 0.89, blue: 1.0)
        case .error: .red
        case .idle: .secondary.opacity(0.55)
        }
    }

    private var statusLabel: String {
        switch effectiveStatus {
        case .idle: "Ready for voice translation"
        case .requested: "Opening recorder"
        case .recording: "Recording in Samantha Key"
        case .ready: "Translation ready"
        case .error: "Needs attention"
        }
    }

    private var displayText: String {
        if effectiveStatus == .requested {
            "Open Samantha Key. Record there, then return here; the translated text inserts automatically."
        } else if effectiveStatus == .recording && effectivePendingText.isEmpty {
            "Recording in Samantha Key. Speak clearly, stop, then return here."
        } else if effectivePendingText.isEmpty {
            "Tap the mic. Samantha records in the app and brings the translation back."
        } else {
            effectivePendingText
        }
    }

    private func compactIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.62))
                .frame(width: 38, height: 34)
                .background(panelBackground, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func keyButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.62))
                .frame(width: 48, height: 34)
                .background(panelBackground, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func keyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.62))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(panelBackground, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func refreshState() {
        refreshDate = Date()
        if localStatus != nil,
           shouldClearLocalFeedbackForSharedState() {
            localStatus = nil
            localPendingText = ""
            localSessionID = ""
        }
        selectedLanguage = AppGroupStore.selectedLanguage
        pendingText = AppGroupStore.pendingText
        status = AppGroupStore.status
        sessionID = AppGroupStore.currentSessionID
        recoverLastReadyResultIfNeeded()
        if effectiveStatus == .ready,
           canInsert,
           effectiveSessionID.isEmpty == false,
           effectiveSessionID != lastInsertedSessionID,
           effectivePendingText != lastInsertedText {
            insertDraft()
        }
    }

    private func applyLocalFeedback(_ notification: Notification) {
        guard let rawStatus = notification.userInfo?[KeyboardLocalFeedback.statusKey] as? String,
              let status = HandoffStatus(rawValue: rawStatus) else { return }
        localPendingText = notification.userInfo?[KeyboardLocalFeedback.textKey] as? String ?? ""
        localSessionID = notification.userInfo?[KeyboardLocalFeedback.sessionIDKey] as? String ?? ""
        localStatus = status
        localFeedbackDate = Date()
    }

    private func beginLocalOpenFeedback() {
        localPendingText = "Opening Samantha Key. If it stays here, open the app manually; recording will start there."
        localSessionID = "local-\(UUID().uuidString)"
        localStatus = .requested
        localFeedbackDate = Date()
    }

    private func insertDraft() {
        let text = effectivePendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        delegate?.insertText(text)
        lastInsertedText = text
        lastInsertedSessionID = effectiveSessionID
        localStatus = nil
        localPendingText = ""
        localSessionID = ""
        pendingText = ""
        status = .idle
    }

    private func recoverLastReadyResultIfNeeded() {
        guard status != .ready,
              pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              AppGroupStore.lastReadyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              Date().timeIntervalSince(AppGroupStore.lastReadyUpdatedAt) < 600 else { return }

        pendingText = AppGroupStore.lastReadyText
        status = .ready
        sessionID = AppGroupStore.lastReadySessionID
    }

    private func shouldClearLocalFeedbackForSharedState() -> Bool {
        let sharedSessionID = AppGroupStore.currentSessionID
        let sharedMovedAfterLocalFeedback = AppGroupStore.updatedAt > localFeedbackDate ||
            AppGroupStore.lastReadyUpdatedAt > localFeedbackDate
        let sharedSessionChanged = !sharedSessionID.isEmpty && sharedSessionID != localSessionID
        return sharedMovedAfterLocalFeedback || sharedSessionChanged
    }
}
