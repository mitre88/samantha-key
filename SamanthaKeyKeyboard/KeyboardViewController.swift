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
        _ = AppGroupStore.startHandoff(language: language)
        let rawURL = "samanthakey://record?source=keyboard&targetLanguage=\(language.rawValue)"
        guard let url = URL(string: rawURL) else { return }
        extensionContext?.open(url) { [weak self] opened in
            if !opened {
                DispatchQueue.main.async { self?.openURLThroughResponderChain(url) }
            }
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

    private func openURLThroughResponderChain(_ url: URL) {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}
