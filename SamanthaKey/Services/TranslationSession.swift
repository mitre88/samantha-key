import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class TranslationSession {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var lastTranscript = ""
    private(set) var lastTranslation = ""
    private(set) var diagnosticMessage = ""

    @ObservationIgnored
    nonisolated(unsafe) private var realtimeClient: RealtimeWebRTCClient?
    @ObservationIgnored
    private weak var entitlementProvider: EntitlementStore?
    @ObservationIgnored
    private var transcriptBuffer = ""
    @ObservationIgnored
    private var translationBuffer = ""
    @ObservationIgnored
    private var shouldPublishToKeyboard = false
    @ObservationIgnored
    private var keyboardSessionID: String?
    @ObservationIgnored
    private var didDetectSpeech = false
    @ObservationIgnored
    private var didReceiveTranslationDelta = false
    @ObservationIgnored
    nonisolated(unsafe) private var pendingPublishTask: Task<Void, Never>?

    private static let maxLiveTextCharacters = 6_000
    private static let liveTextOverflowSlack = 512
    private static let publishDebounceNanoseconds: UInt64 = 80_000_000

    deinit {
        pendingPublishTask?.cancel()
        realtimeClient?.disconnect()
    }

    func configure(entitlementProvider: EntitlementStore) async {
        self.entitlementProvider = entitlementProvider
    }

    func start(outputLanguage: AppLanguage, publishToKeyboard: Bool = false, sessionID: String? = nil) async {
        let activeSessionID = sessionID?.isEmpty == false ? sessionID : (AppGroupStore.currentSessionID.isEmpty ? nil : AppGroupStore.currentSessionID)
        guard state != .preparing && state != .listening else {
            if publishToKeyboard {
                AppGroupStore.publish(text: lastTranslation, status: .recording, sessionID: activeSessionID ?? keyboardSessionID)
            }
            return
        }
        guard let entitlement = await entitlementProvider?.currentEntitlementPayload() else {
            state = .error(BackendError.missingEntitlement.localizedDescription)
            note(BackendError.missingEntitlement.localizedDescription)
            if publishToKeyboard {
                AppGroupStore.publish(text: BackendError.missingEntitlement.localizedDescription, status: .error, sessionID: activeSessionID)
            }
            return
        }

        do {
            state = .preparing
            shouldPublishToKeyboard = publishToKeyboard
            keyboardSessionID = activeSessionID
            didDetectSpeech = false
            didReceiveTranslationDelta = false
            if publishToKeyboard {
                AppGroupStore.publish(text: "", status: .recording, sessionID: activeSessionID)
            }
            resetLiveText()

            note("Requesting microphone permission.")
            guard await Self.requestMicrophoneAccess() else {
                throw RealtimeSessionError.microphoneDenied
            }

            note("Requesting realtime token.")
            let tokenResponse = try await BackendClient().realtimeToken(entitlement: entitlement, outputLanguage: outputLanguage)
            guard let token = tokenResponse.token else { throw BackendError.missingRealtimeToken }
            note("Realtime token received.")

            let client = RealtimeWebRTCClient()
            realtimeClient = client

            try await client.connect(
                token: token,
                endpoint: tokenResponse.webRTCEndpoint ?? URL(string: "https://api.openai.com/v1/realtime/translations/calls")!,
                outputLanguage: outputLanguage,
                onEvent: { [weak self] text in
                    self?.handle(eventText: text)
                },
                onDiagnostic: { [weak self] message in
                    self?.note(message)
                },
                onFailure: { [weak self] message in
                    self?.fail(message)
                }
            )

            state = .listening
            note("Listening for translated speech.")
        } catch {
            stop()
            state = .error(error.localizedDescription)
            note(error.localizedDescription)
            if publishToKeyboard {
                AppGroupStore.publish(text: error.localizedDescription, status: .error, sessionID: activeSessionID)
            }
        }
    }

    func stop() {
        flushBufferedText()
        let activeSessionID = keyboardSessionID ?? (AppGroupStore.currentSessionID.isEmpty ? nil : AppGroupStore.currentSessionID)
        if shouldPublishToKeyboard {
            if lastTranslation.isEmpty {
                AppGroupStore.publish(
                    text: "No translation was produced. Keep Samantha Key open while speaking, then return to the keyboard.",
                    status: .error,
                    sessionID: activeSessionID
                )
            } else {
                AppGroupStore.publish(text: lastTranslation, status: .ready, sessionID: activeSessionID)
            }
        }
        shouldPublishToKeyboard = false
        keyboardSessionID = nil
        realtimeClient?.disconnect()
        realtimeClient = nil
        if case .error = state { return }
        state = .idle
        note("")
    }

    func updateOutputLanguage(_ outputLanguage: AppLanguage) {
        guard case .listening = state, let realtimeClient else { return }
        do {
            try realtimeClient.updateOutputLanguage(outputLanguage)
            resetLiveText()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func handle(eventText text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            break
        case let eventType where Self.isOutputTranslationDelta(eventType):
            if let delta = Self.textPayload(from: event) { appendTranslationDelta(delta) }
        case let eventType where Self.isInputTranscriptDelta(eventType):
            if let delta = Self.textPayload(from: event) { appendTranscriptDelta(delta) }
        case let eventType where Self.isInputTranscriptDone(eventType):
            if let transcript = Self.textPayload(from: event) {
                transcriptBuffer = Self.trimmedLiveText(transcript)
                flushBufferedText()
            }
        case let eventType where Self.isOutputTranslationDone(eventType):
            if let transcript = Self.textPayload(from: event) {
                translationBuffer = Self.trimmedLiveText(transcript)
                flushBufferedText()
            }
        case "input_audio_buffer.speech_started", "session.input_audio_buffer.speech_started":
            if !didDetectSpeech {
                didDetectSpeech = true
                note("Speech detected.")
            }
            resetLiveText()
        case "response.done", "response.audio.done":
            flushBufferedText()
        case "error":
            fail(Self.errorMessage(from: event))
        default:
            break
        }
    }

    private func fail(_ message: String) {
        let publishError = shouldPublishToKeyboard
        let activeSessionID = keyboardSessionID
        shouldPublishToKeyboard = false
        if publishError {
            AppGroupStore.publish(text: message, status: .error, sessionID: activeSessionID)
        }
        stop()
        state = .error(message)
        note(message)
    }

    private func appendTranscriptDelta(_ delta: String) {
        guard delta.isEmpty == false else { return }
        transcriptBuffer.append(delta)
        trimBufferIfNeeded(&transcriptBuffer)
        scheduleBufferedPublish()
    }

    private func appendTranslationDelta(_ delta: String) {
        guard delta.isEmpty == false else { return }
        if !didReceiveTranslationDelta {
            didReceiveTranslationDelta = true
            note("Translation stream received.")
        }
        translationBuffer.append(delta)
        trimBufferIfNeeded(&translationBuffer)
        scheduleBufferedPublish()
    }

    private func resetLiveText() {
        transcriptBuffer = ""
        translationBuffer = ""
        flushBufferedText()
    }

    private func scheduleBufferedPublish() {
        pendingPublishTask?.cancel()
        pendingPublishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.publishDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.publishBufferedTextFromTask()
        }
    }

    private func publishBufferedTextFromTask() {
        pendingPublishTask = nil
        publishBufferedText()
    }

    private func flushBufferedText() {
        pendingPublishTask?.cancel()
        pendingPublishTask = nil
        publishBufferedText()
    }

    private func publishBufferedText() {
        if lastTranscript != transcriptBuffer {
            lastTranscript = transcriptBuffer
        }

        if lastTranslation != translationBuffer {
            lastTranslation = translationBuffer
            if shouldPublishToKeyboard {
                AppGroupStore.publish(text: translationBuffer, status: .recording, sessionID: keyboardSessionID)
            }
        }
    }

    private func trimBufferIfNeeded(_ text: inout String) {
        guard text.count > Self.maxLiveTextCharacters + Self.liveTextOverflowSlack else { return }
        text = String(text.suffix(Self.maxLiveTextCharacters))
    }

    private static func errorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let code = error["code"] as? String { return code }
        }
        return "The realtime voice session reported an error."
    }

    private static func trimmedLiveText(_ text: String) -> String {
        guard text.count > maxLiveTextCharacters else { return text }
        return String(text.suffix(maxLiveTextCharacters))
    }

    private static func requestMicrophoneAccess() async -> Bool {
        let application = AVAudioApplication.shared
        switch application.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func note(_ message: String) {
        diagnosticMessage = message
    }

    private static func textPayload(from event: [String: Any]) -> String? {
        for key in ["delta", "text", "transcript", "translation", "output_text"] {
            if let value = event[key] as? String, value.isEmpty == false {
                return value
            }
        }

        if let item = event["item"] as? [String: Any] {
            return textPayload(from: item)
        }

        if let response = event["response"] as? [String: Any] {
            return textPayload(from: response)
        }

        if let content = event["content"] as? [[String: Any]] {
            for part in content {
                if let value = textPayload(from: part) {
                    return value
                }
            }
        }

        if let output = event["output"] as? [[String: Any]] {
            for part in output {
                if let value = textPayload(from: part) {
                    return value
                }
            }
        }

        return nil
    }

    private static func isInputTranscriptDelta(_ type: String) -> Bool {
        [
            "session.input_transcript.delta",
            "conversation.item.input_audio_transcription.delta",
            "input_audio_buffer.transcription.delta"
        ].contains(type)
    }

    private static func isInputTranscriptDone(_ type: String) -> Bool {
        [
            "session.input_transcript.completed",
            "session.input_transcript.done",
            "conversation.item.input_audio_transcription.completed",
            "conversation.item.input_audio_transcription.done",
            "input_audio_buffer.transcription.completed",
            "input_audio_buffer.transcription.done"
        ].contains(type)
    }

    private static func isOutputTranslationDelta(_ type: String) -> Bool {
        [
            "session.output_transcript.delta",
            "response.output_audio_transcript.delta",
            "response.audio_transcript.delta",
            "response.output_text.delta",
            "response.text.delta",
            "translation.output_text.delta",
            "translation.transcript.delta"
        ].contains(type)
    }

    private static func isOutputTranslationDone(_ type: String) -> Bool {
        [
            "session.output_transcript.done",
            "session.output_transcript.completed",
            "response.output_audio_transcript.done",
            "response.audio_transcript.done",
            "response.output_text.done",
            "response.text.done",
            "translation.output_text.done",
            "translation.output_text.completed",
            "translation.transcript.done",
            "translation.transcript.completed"
        ].contains(type)
    }
}

private enum RealtimeSessionError: LocalizedError {
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Enable it in iOS Settings, then try Speak to translate again."
        }
    }
}
