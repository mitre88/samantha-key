import SwiftUI

struct SettingsView: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    @AppStorage("outputLanguage") private var outputLanguageRaw = AppLanguage.english.rawValue

    var body: some View {
        Form {
            Section {
                Picker("settings.output_language", selection: $outputLanguageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            }
            .onChange(of: outputLanguageRaw) { _, newValue in
                AppGroupStore.selectedLanguage = AppLanguage.resolved(from: newValue)
            }

            Section("keyboard.setup.nav") {
                NavigationLink {
                    KeyboardSetupView()
                } label: {
                    Label("keyboard.setup.title", systemImage: "keyboard")
                }
                Text("keyboard.setup.short_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("settings.subscription") {
                Button("paywall.restore") {
                    Task { await entitlementStore.restore() }
                }
                Text("settings.subscription.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("settings.privacy") {
                Text("settings.privacy.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("settings.privacy.link", destination: URL(string: "https://samantha-key-support.vercel.app/#privacy")!)
                Link("settings.support.link", destination: URL(string: "https://samantha-key-support.vercel.app/#support")!)
            }
        }
        .navigationTitle("settings.title")
    }
}
