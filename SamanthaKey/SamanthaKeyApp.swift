import SwiftUI

@main
struct SamanthaKeyApp: App {
    @State private var entitlementStore = EntitlementStore()
    @State private var translationSession = TranslationSession()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(entitlementStore)
                .environment(translationSession)
                .task {
                    await entitlementStore.refresh()
                    await translationSession.configure(entitlementProvider: entitlementStore)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        translationSession.stop()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "samanthakey" else { return }
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let languageCode = components?.queryItems?.first(where: { $0.name == "targetLanguage" })?.value
                    let language = AppLanguage.resolved(from: languageCode)
                    _ = AppGroupStore.startHandoff(language: language)
                    Task {
                        await translationSession.start(outputLanguage: language, publishToKeyboard: true)
                    }
                }
        }
    }
}
