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

/// Debug-only screenshot fixtures. Every screen is a shipping view filled with sample content;
/// none of this is compiled into Release builds.
struct ScreenshotShowcaseView: View {
    let screen: String
    @Environment(TranslationSession.self) private var translationSession
    @State private var hasSampleTranslation = false

    private static let sampleTranscript = "Hola, llego en diez minutos. ¿Puedes guardar una mesa cerca de la ventana?"
    private static let sampleTranslation = "Hi, I’ll arrive in ten minutes. Can you save a table near the window?"

    var body: some View {
        switch screen {
        case "setup":
            NavigationStack { KeyboardSetupView() }
                .tint(.primary)
        default:
            // The translator ("translator") or keyboard-recording ("handoff-live") screen, shown once the
            // sample translation is in place so it opens at its resting scroll position.
            ZStack {
                if hasSampleTranslation {
                    if screen == "handoff-live" {
                        KeyboardHandoffRecordingView()
                    } else {
                        TranslatorView(outputLanguage: .english)
                    }
                }
            }
            .task {
                translationSession.showScreenshotPreview(transcript: Self.sampleTranscript, translation: Self.sampleTranslation)
                hasSampleTranslation = true
            }
        }
    }
}
#endif
