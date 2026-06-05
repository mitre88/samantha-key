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

            VStack(spacing: 10) {
                topBar
                draftPanel
                controlRow
                utilityRow
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
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
        HStack(spacing: 8) {
            if needsInputModeSwitchKey {
                keyButton(systemImage: "globe") { delegate?.switchToNextKeyboard() }
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                Text("Samantha Key")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary.opacity(0.86))

            Spacer(minLength: 8)

            Picker("", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.plainName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.primary)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(maxWidth: 132)
        }
    }

    private var draftPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                if canInsert {
                    Button("Insert") { insertDraft() }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.60, green: 0.96, blue: 0.79), in: Capsule())
                }
            }

            Text(displayText)
                .font(.system(size: 15, weight: canInsert ? .semibold : .regular, design: .rounded))
                .foregroundStyle(effectiveStatus == .error ? .red : (canInsert ? .primary : .secondary))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .contentTransition(.opacity)
        }
        .padding(12)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        .font(.system(size: 18, weight: .bold))
                    Text(effectiveStatus == .recording ? "Listening in app" : "Speak to translate")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .foregroundStyle(Color(white: 0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
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
                    .frame(width: 54, height: 54)
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
            "Open Samantha Key now. Recording will start there, then return here to insert the translation."
        } else if effectiveStatus == .recording && effectivePendingText.isEmpty {
            "Recording in Samantha Key. Speak clearly, then return to this keyboard."
        } else if effectivePendingText.isEmpty {
            "Tap the microphone. Samantha records in the app, translates, then places the text back here."
        } else {
            effectivePendingText
        }
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
           AppGroupStore.updatedAt > localFeedbackDate,
           AppGroupStore.currentSessionID == localSessionID {
            localStatus = nil
            localPendingText = ""
            localSessionID = ""
        }
        selectedLanguage = AppGroupStore.selectedLanguage
        pendingText = AppGroupStore.pendingText
        status = AppGroupStore.status
        sessionID = AppGroupStore.currentSessionID
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
}
