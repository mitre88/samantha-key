import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, SamanthaKeyboardActionDelegate {
    private var hostingController: UIHostingController<SamanthaKeyboardView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingController?.rootView = makeKeyboardView()
    }

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
        AppGroupStore.clearPublishedText()
        hostingController?.rootView = makeKeyboardView()
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func insertSpace() {
        textDocumentProxy.insertText(" ")
    }

    func insertReturn() {
        textDocumentProxy.insertText("\n")
    }

    func switchToNextKeyboard() {
        advanceToNextInputMode()
    }

    func clearDraft() {
        AppGroupStore.clearPublishedText()
        hostingController?.rootView = makeKeyboardView()
    }

    func openRecorder() {
        let language = AppGroupStore.selectedLanguage
        let sessionID = UUID().uuidString
        publishKeyboardState(
            text: "Opening Samantha Key...",
            status: .requested,
            sessionID: sessionID
        )

        guard AppGroupStore.isSharedStateWritable else {
            publishKeyboardState(
                text: "Turn on Allow Full Access for Samantha Key in iOS Keyboard settings, then try again.",
                status: .error,
                sessionID: sessionID
            )
            hostingController?.rootView = makeKeyboardView()
            return
        }

        _ = AppGroupStore.startHandoff(language: language, sessionID: sessionID)
        guard let url = recorderURL(language: language, sessionID: sessionID) else {
            publishKeyboardState(
                text: "Could not create the Samantha Key recorder link.",
                status: .error,
                sessionID: sessionID
            )
            hostingController?.rootView = makeKeyboardView()
            return
        }

        if openURLThroughResponderChain(url) {
            scheduleHandoffWatchdog(sessionID: sessionID)
        } else if let extensionContext {
            extensionContext.open(url) { [weak self] opened in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if opened {
                        self.scheduleHandoffWatchdog(sessionID: sessionID)
                    } else {
                        self.handleOpenFailure(url: url, sessionID: sessionID)
                    }
                }
            }
        } else {
            handleOpenFailure(url: url, sessionID: sessionID)
        }

        hostingController?.rootView = makeKeyboardView()
    }

    private func buildKeyboard() {
        let keyboardView = makeKeyboardView()
        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: 292)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
    }

    private func makeKeyboardView() -> SamanthaKeyboardView {
        SamanthaKeyboardView(
            delegate: self,
            needsInputModeSwitchKey: needsInputModeSwitchKey
        )
    }

    private func recorderURL(language: AppLanguage, sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "samanthakey"
        components.host = "record"
        components.queryItems = [
            URLQueryItem(name: "source", value: "keyboard"),
            URLQueryItem(name: "targetLanguage", value: language.rawValue),
            URLQueryItem(name: "sessionID", value: sessionID)
        ]
        return components.url
    }

    private func scheduleHandoffWatchdog(sessionID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard AppGroupStore.currentSessionID == sessionID,
                  AppGroupStore.status == .requested else { return }
            self.publishKeyboardState(
                text: "Open Samantha Key now. The app will start recording this keyboard request automatically.",
                status: .requested,
                sessionID: sessionID
            )
            self.hostingController?.rootView = self.makeKeyboardView()
        }
    }

    private func handleOpenFailure(url: URL, sessionID: String) {
        let didAttemptFallback = openURLThroughResponderChain(url)
        if !didAttemptFallback {
            publishKeyboardState(
                text: "Open Samantha Key now. Recording will start automatically for this keyboard request.",
                status: .requested,
                sessionID: sessionID
            )
        }
        scheduleHandoffWatchdog(sessionID: sessionID)
        hostingController?.rootView = makeKeyboardView()
    }

    private func publishKeyboardState(text: String, status: HandoffStatus, sessionID: String) {
        AppGroupStore.publish(text: text, status: status, sessionID: sessionID)
        KeyboardLocalFeedback.post(text: text, status: status, sessionID: sessionID)
    }

    @discardableResult
    private func openURLThroughResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = view
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }
}
