import AVFoundation
import Foundation
import Observation
import UIKit

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
    private var activeEntitlementPayload: EntitlementPayload?
    @ObservationIgnored
    private var activeOutputLanguage = AppLanguage.english
    @ObservationIgnored
    private var didDetectSpeech = false
    @ObservationIgnored
    private var didReceiveTranslationDelta = false
    @ObservationIgnored
    nonisolated(unsafe) private var pendingPublishTask: Task<Void, Never>?
    @ObservationIgnored
    private var keyboardAudioRecorder: AVAudioRecorder?
    @ObservationIgnored
    private var keyboardAudioURL: URL?

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
            activeEntitlementPayload = entitlement
            activeOutputLanguage = outputLanguage
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

            if publishToKeyboard {
                try startKeyboardAudioRecording()
                state = .listening
                note("Recording voice for keyboard.")
                AppGroupStore.publish(text: "", status: .recording, sessionID: activeSessionID)
                return
            }

            do {
                try await connectRealtime(entitlement: entitlement, outputLanguage: outputLanguage)
            } catch {
                guard Self.shouldRetryRealtimeConnection(after: error) else { throw error }
                note("Realtime negotiation closed early. Retrying once.")
                realtimeClient?.disconnect()
                realtimeClient = nil
                try await Task.sleep(nanoseconds: 250_000_000)
                try await connectRealtime(entitlement: entitlement, outputLanguage: outputLanguage)
            }

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
        let recordedAudioData = finishKeyboardAudioRecording()
        let activeSessionID = keyboardSessionID ?? (AppGroupStore.currentSessionID.isEmpty ? nil : AppGroupStore.currentSessionID)
        let finalTranslation = lastTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTranscript = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackEntitlement = activeEntitlementPayload
        let fallbackLanguage = activeOutputLanguage
        if shouldPublishToKeyboard {
            if !finalTranslation.isEmpty {
                AppGroupStore.publishReadyText(finalTranslation, sessionID: activeSessionID)
            } else if !finalTranscript.isEmpty, let fallbackEntitlement {
                AppGroupStore.publish(
                    text: "Finalizing translation...",
                    status: .recording,
                    sessionID: activeSessionID
                )
                Task { [weak self] in
                    await self?.publishTextFallback(
                        sourceText: finalTranscript,
                        entitlement: fallbackEntitlement,
                        outputLanguage: fallbackLanguage,
                        sessionID: activeSessionID
                    )
                }
            } else if let recordedAudioData, let fallbackEntitlement {
                AppGroupStore.publish(
                    text: "Transcribing recorded voice...",
                    status: .recording,
                    sessionID: activeSessionID
                )
                Task { [weak self] in
                    await self?.publishAudioFallback(
                        audioData: recordedAudioData,
                        entitlement: fallbackEntitlement,
                        outputLanguage: fallbackLanguage,
                        sessionID: activeSessionID
                    )
                }
            } else {
                AppGroupStore.publish(
                    text: "No voice was captured. Keep Samantha Key open while speaking, then return to the keyboard.",
                    status: .error,
                    sessionID: activeSessionID
                )
            }
        }
        shouldPublishToKeyboard = false
        keyboardSessionID = nil
        activeEntitlementPayload = nil
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

    private func connectRealtime(entitlement: EntitlementPayload, outputLanguage: AppLanguage) async throws {
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
    }

    private static func shouldRetryRealtimeConnection(after error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("closed") ||
            message.contains("wrong state") ||
            message.contains("signaling")
    }

    private func startKeyboardAudioRecording() throws {
        finishKeyboardAudioRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try audioSession.setActive(true)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samantha-key-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RealtimeSessionError.audioRecorderUnavailable
        }

        keyboardAudioURL = fileURL
        keyboardAudioRecorder = recorder
    }

    @discardableResult
    private func finishKeyboardAudioRecording() -> Data? {
        keyboardAudioRecorder?.stop()
        keyboardAudioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = keyboardAudioURL else { return nil }
        keyboardAudioURL = nil
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = try? Data(contentsOf: url), data.count > 1_024 else { return nil }
        return data
    }

    private func publishTextFallback(
        sourceText: String,
        entitlement: EntitlementPayload,
        outputLanguage: AppLanguage,
        sessionID: String?
    ) async {
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SamanthaKeyTextFallback") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        do {
            let translated = try await BackendClient().translateText(
                entitlement: entitlement,
                text: sourceText,
                outputLanguage: outputLanguage
            )
            let finalText = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalText.isEmpty {
                AppGroupStore.publish(
                    text: "Samantha captured your voice but could not produce a translated text. Try again with a shorter phrase.",
                    status: .error,
                    sessionID: sessionID
                )
            } else {
                AppGroupStore.publishReadyText(finalText, sessionID: sessionID)
            }
        } catch {
            AppGroupStore.publish(
                text: "Captured voice, but text translation fallback failed: \(error.localizedDescription)",
                status: .error,
                sessionID: sessionID
            )
        }
    }

    private func publishAudioFallback(
        audioData: Data,
        entitlement: EntitlementPayload,
        outputLanguage: AppLanguage,
        sessionID: String?
    ) async {
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SamanthaKeyAudioFallback") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        do {
            let translated = try await BackendClient().translateAudio(
                entitlement: entitlement,
                audioData: audioData,
                outputLanguage: outputLanguage
            )
            let transcript = translated.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = translated.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                lastTranscript = transcript
            }
            if finalText.isEmpty {
                AppGroupStore.publish(
                    text: "Samantha captured audio but could not produce translated text. Try again with a shorter phrase.",
                    status: .error,
                    sessionID: sessionID
                )
            } else {
                lastTranslation = finalText
                AppGroupStore.publishReadyText(finalText, sessionID: sessionID)
            }
        } catch {
            AppGroupStore.publish(
                text: "Captured audio, but transcription failed: \(error.localizedDescription)",
                status: .error,
                sessionID: sessionID
            )
        }
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
        if [
            "session.input_transcript.delta",
            "conversation.item.input_audio_transcription.delta",
            "input_audio_buffer.transcription.delta",
            "transcript.text.delta"
        ].contains(type) {
            return true
        }
        return (type.contains("input_audio_transcription") || type.contains("input_transcript"))
            && type.hasSuffix(".delta")
    }

    private static func isInputTranscriptDone(_ type: String) -> Bool {
        if [
            "session.input_transcript.completed",
            "session.input_transcript.done",
            "conversation.item.input_audio_transcription.completed",
            "conversation.item.input_audio_transcription.done",
            "input_audio_buffer.transcription.completed",
            "input_audio_buffer.transcription.done",
            "transcript.text.done"
        ].contains(type) {
            return true
        }
        return (type.contains("input_audio_transcription") || type.contains("input_transcript"))
            && (type.hasSuffix(".done") || type.hasSuffix(".completed"))
    }

    private static func isOutputTranslationDelta(_ type: String) -> Bool {
        if [
            "session.output_transcript.delta",
            "response.output_audio_transcript.delta",
            "response.audio_transcript.delta",
            "response.output_text.delta",
            "response.text.delta",
            "translation.output_text.delta",
            "translation.transcript.delta"
        ].contains(type) {
            return true
        }
        return (type.contains("translation") ||
            type.contains("output_audio_transcript") ||
            type.contains("audio_transcript") ||
            type.contains("output_text"))
            && type.hasSuffix(".delta")
    }

    private static func isOutputTranslationDone(_ type: String) -> Bool {
        if [
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
        ].contains(type) {
            return true
        }
        return (type.contains("translation") ||
            type.contains("output_audio_transcript") ||
            type.contains("audio_transcript") ||
            type.contains("output_text"))
            && (type.hasSuffix(".done") || type.hasSuffix(".completed"))
    }
}

private enum RealtimeSessionError: LocalizedError {
    case microphoneDenied
    case audioRecorderUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Enable it in iOS Settings, then try Speak to translate again."
        case .audioRecorderUnavailable:
            "Samantha Key could not start recording. Close the app using the microphone and try again."
        }
    }
}
