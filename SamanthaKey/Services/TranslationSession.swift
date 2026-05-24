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

    func start(outputLanguage: AppLanguage, publishToKeyboard: Bool = false) async {
        guard state != .preparing && state != .listening else { return }
        guard let entitlement = await entitlementProvider?.currentEntitlementPayload() else {
            state = .error(BackendError.missingEntitlement.localizedDescription)
            if publishToKeyboard {
                AppGroupStore.publish(text: BackendError.missingEntitlement.localizedDescription, status: .error)
            }
            return
        }

        do {
            state = .preparing
            shouldPublishToKeyboard = publishToKeyboard
            if publishToKeyboard {
                AppGroupStore.publish(text: "", status: .recording)
            }
            resetLiveText()

            let tokenResponse = try await BackendClient().realtimeToken(entitlement: entitlement, outputLanguage: outputLanguage)
            guard let token = tokenResponse.token else { throw BackendError.missingRealtimeToken }

            let client = RealtimeWebRTCClient()
            realtimeClient = client

            try await client.connect(
                token: token,
                endpoint: tokenResponse.webRTCEndpoint ?? URL(string: "https://api.openai.com/v1/realtime/translations/calls")!,
                outputLanguage: outputLanguage,
                onEvent: { [weak self] text in
                    self?.handle(eventText: text)
                },
                onFailure: { [weak self] message in
                    self?.fail(message)
                }
            )

            state = .listening
        } catch {
            stop()
            state = .error(error.localizedDescription)
            if publishToKeyboard {
                AppGroupStore.publish(text: error.localizedDescription, status: .error)
            }
        }
    }

    func stop() {
        flushBufferedText()
        if shouldPublishToKeyboard {
            AppGroupStore.publish(text: lastTranslation, status: lastTranslation.isEmpty ? .idle : .ready)
        }
        shouldPublishToKeyboard = false
        realtimeClient?.disconnect()
        realtimeClient = nil
        if case .error = state { return }
        state = .idle
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
        case "session.output_transcript.delta", "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.output_text.delta", "response.text.delta":
            if let delta = event["delta"] as? String { appendTranslationDelta(delta) }
        case "session.input_transcript.delta":
            if let delta = event["delta"] as? String { appendTranscriptDelta(delta) }
        case "conversation.item.input_audio_transcription.completed", "input_audio_buffer.transcription.completed", "session.input_transcript.completed":
            if let transcript = event["transcript"] as? String {
                transcriptBuffer = Self.trimmedLiveText(transcript)
                flushBufferedText()
            }
        case "response.output_audio_transcript.done", "response.audio_transcript.done", "response.output_text.done", "response.text.done":
            if let transcript = event["transcript"] as? String {
                translationBuffer = Self.trimmedLiveText(transcript)
                flushBufferedText()
            }
        case "input_audio_buffer.speech_started", "session.input_audio_buffer.speech_started":
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
        shouldPublishToKeyboard = false
        if publishError {
            AppGroupStore.publish(text: message, status: .error)
        }
        stop()
        state = .error(message)
    }

    private func appendTranscriptDelta(_ delta: String) {
        guard delta.isEmpty == false else { return }
        transcriptBuffer.append(delta)
        trimBufferIfNeeded(&transcriptBuffer)
        scheduleBufferedPublish()
    }

    private func appendTranslationDelta(_ delta: String) {
        guard delta.isEmpty == false else { return }
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
                AppGroupStore.publish(text: translationBuffer, status: .recording)
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
}
