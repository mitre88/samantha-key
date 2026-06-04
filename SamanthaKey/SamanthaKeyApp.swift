import Observation
import SwiftUI

@main
struct SamanthaKeyApp: App {
    @State private var entitlementStore = EntitlementStore()
    @State private var translationSession = TranslationSession()
    @State private var keyboardHandoff = KeyboardHandoffCoordinator()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(entitlementStore)
                .environment(translationSession)
                .environment(keyboardHandoff)
                .task {
                    keyboardHandoff.configure(entitlementStore: entitlementStore, translationSession: translationSession)
                    await entitlementStore.refresh()
                    await translationSession.configure(entitlementProvider: entitlementStore)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        keyboardHandoff.handleSceneBackground()
                    }
                }
                .onOpenURL { url in
                    keyboardHandoff.configure(entitlementStore: entitlementStore, translationSession: translationSession)
                    Task {
                        await keyboardHandoff.handle(url: url)
                    }
                }
        }
    }
}

@MainActor
@Observable
final class KeyboardHandoffCoordinator {
    private weak var entitlementStore: EntitlementStore?
    private weak var translationSession: TranslationSession?

    private(set) var isActive = false
    private(set) var sessionID = ""
    private(set) var outputLanguage = AppLanguage.english
    private(set) var message = "Preparing keyboard recording..."

    func configure(entitlementStore: EntitlementStore, translationSession: TranslationSession) {
        self.entitlementStore = entitlementStore
        self.translationSession = translationSession
    }

    func handle(url: URL) async {
        guard url.scheme == "samanthakey", url.host == "record" else { return }
        guard let entitlementStore, let translationSession else {
            AppGroupStore.publish(text: "Samantha Key is still preparing. Try again.", status: .error)
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let languageCode = components?.queryItems?.first(where: { $0.name == "targetLanguage" })?.value
        let incomingSessionID = components?.queryItems?.first(where: { $0.name == "sessionID" })?.value
        let resolvedSessionID = incomingSessionID?.isEmpty == false ? incomingSessionID! : (AppGroupStore.currentSessionID.isEmpty ? UUID().uuidString : AppGroupStore.currentSessionID)
        let language = AppLanguage.resolved(from: languageCode)

        sessionID = resolvedSessionID
        outputLanguage = language
        isActive = true
        message = "Opening microphone..."
        _ = AppGroupStore.startHandoff(language: language, sessionID: resolvedSessionID)

        await entitlementStore.refresh()
        await translationSession.configure(entitlementProvider: entitlementStore)
        await translationSession.start(outputLanguage: language, publishToKeyboard: true, sessionID: resolvedSessionID)
        if case .error = translationSession.state {
            message = "Keyboard recording needs attention."
        } else {
            message = "Recording for keyboard. Speak, then return to your text field."
        }
    }

    func stop() {
        translationSession?.stop()
        isActive = false
        message = "Translation sent back to keyboard."
    }

    func handleSceneBackground() {
        translationSession?.stop()
        if isActive {
            isActive = false
            message = "Translation sent back to keyboard."
        }
    }
}
