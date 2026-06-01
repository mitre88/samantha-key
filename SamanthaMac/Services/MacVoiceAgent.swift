import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MacVoiceAgent {
    var state: MacAgentState = .idle
    var logs: [AgentLogEntry] = [
        AgentLogEntry(kind: .info, message: "Press Start or use Option-Command-Space to talk.")
    ]
    var pendingApproval: ToolApprovalRequest?
    var assistantDraft = ""
    var userDraft = ""

    @ObservationIgnored private var socket: OpenAIRealtimeSocket?
    @ObservationIgnored private let microphone = MicrophoneStreamer()
    @ObservationIgnored private let speaker = RealtimeAudioPlayer()
    @ObservationIgnored private let toolRouter = LocalToolRouter()
    @ObservationIgnored private var pendingCall: PendingFunctionCall?
    @ObservationIgnored private var handledCallIDs = Set<String>()
    @ObservationIgnored private var hotkeyMonitors: [Any] = []

    var isRunning: Bool {
        if case .listening = state { return true }
        if case .connecting = state { return true }
        if case .acting = state { return true }
        return false
    }

    var maskedAPIKey: String {
        APIKeyStore.maskedValue
    }

    func installHotkeyMonitor() {
        guard hotkeyMonitors.isEmpty else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.contains(.option),
                  event.modifierFlags.contains(.command) else { return }
            Task { @MainActor in
                await self?.toggleListening()
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            hotkeyMonitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        if let local {
            hotkeyMonitors.append(local)
        }
    }

    func saveAPIKey(_ rawValue: String) {
        do {
            try APIKeyStore.save(rawValue)
            append(.info, "API key saved in local Keychain.")
        } catch {
            fail(error.localizedDescription)
        }
    }

    func toggleListening() async {
        if isRunning || pendingApproval != nil {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard socket == nil else { return }
        guard let apiKey = APIKeyStore.resolvedKey(),
              apiKey.isEmpty == false else {
            fail("OpenAI API key was not found in Keychain or local configuration.")
            return
        }

        do {
            state = .connecting
            assistantDraft = ""
            userDraft = ""
            handledCallIDs.removeAll()
            append(.info, "Connecting to gpt-realtime-2.")

            let realtime = OpenAIRealtimeSocket(
                apiKey: apiKey,
                model: "gpt-realtime-2",
                safetyIdentifier: stableSafetyIdentifier(),
                onEvent: { [weak self] text in
                    self?.handleEvent(text)
                },
                onError: { [weak self] message in
                    self?.fail(message)
                }
            )
            socket = realtime
            try await realtime.connect()
            try await realtime.configureSession(instructions: Self.instructions)
            try speaker.start()
            try microphone.start { [weak self] data in
                Task { @MainActor in
                    await self?.sendAudio(data)
                }
            }

            state = .listening
            append(.info, "Listening. Ask Samantha to open apps, inspect the screen, or run safe local commands.")
        } catch {
            stop()
            fail(error.localizedDescription)
        }
    }

    func stop() {
        microphone.stop()
        speaker.stop()
        socket?.close()
        socket = nil
        pendingCall = nil
        pendingApproval = nil
        assistantDraft = ""
        userDraft = ""
        if case .error = state { return }
        state = .idle
        append(.info, "Stopped.")
    }

    func approvePendingTool() async {
        guard let call = pendingCall else { return }
        pendingCall = nil
        pendingApproval = nil
        await executeAndReturn(call)
    }

    func rejectPendingTool() async {
        guard let call = pendingCall else { return }
        pendingCall = nil
        pendingApproval = nil
        append(.tool, "Denied \(call.name).")
        do {
            try await socket?.sendFunctionOutput(
                callID: call.callID,
                output: ToolExecutionOutput(ok: false, text: "The user denied this local action.").jsonString
            )
            state = .listening
        } catch {
            fail(error.localizedDescription)
        }
    }

    func clearLogs() {
        logs.removeAll(keepingCapacity: true)
        append(.info, "Log cleared.")
    }

    private func sendAudio(_ data: Data) async {
        do {
            try await socket?.sendAudio(data)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            break
        case "input_audio_buffer.speech_started":
            userDraft = "Listening..."
        case "input_audio_buffer.speech_stopped":
            userDraft = "Processing..."
        case "conversation.item.input_audio_transcription.completed", "input_audio_buffer.transcription.completed":
            if let transcript = event["transcript"] as? String, transcript.isEmpty == false {
                userDraft = ""
                append(.user, transcript)
            }
        case "response.output_audio.delta":
            if let delta = event["delta"] as? String,
               let audio = Data(base64Encoded: delta) {
                speaker.playPCM16(audio)
            }
        case "response.output_audio_transcript.delta", "response.output_text.delta", "response.text.delta":
            if let delta = event["delta"] as? String {
                assistantDraft.append(delta)
            }
        case "response.output_audio_transcript.done", "response.output_text.done", "response.text.done":
            flushAssistantDraft(fallback: event["transcript"] as? String)
        case "response.function_call_arguments.done":
            if let call = functionCall(from: event) {
                Task { await handleFunctionCall(call) }
            }
        case "response.output_item.done":
            if let item = event["item"] as? [String: Any], let call = functionCall(fromOutputItem: item) {
                Task { await handleFunctionCall(call) }
            }
        case "response.done":
            flushAssistantDraft(fallback: nil)
            for call in functionCalls(fromResponseDoneEvent: event) {
                Task { await handleFunctionCall(call) }
            }
        case "error":
            fail(Self.errorMessage(from: event))
        default:
            break
        }
    }

    private func handleFunctionCall(_ call: PendingFunctionCall) async {
        guard handledCallIDs.contains(call.callID) == false else { return }
        handledCallIDs.insert(call.callID)

        let arguments = ToolJSON.decodeArguments(call.argumentsJSON)
        switch toolRouter.assess(name: call.name, arguments: arguments) {
        case .executeNow:
            await executeAndReturn(call)
        case .needsApproval(let reason):
            pendingCall = call
            pendingApproval = ToolApprovalRequest(
                callID: call.callID,
                name: call.name,
                arguments: ToolJSON.sendableArguments(arguments),
                reason: reason
            )
            state = .needsApproval
            append(.tool, "\(call.name) needs approval.")
        }
    }

    private func executeAndReturn(_ call: PendingFunctionCall) async {
        let arguments = ToolJSON.decodeArguments(call.argumentsJSON)
        state = .acting(call.name)
        append(.tool, "Running \(call.name).")
        let result = await toolRouter.execute(name: call.name, arguments: arguments)
        append(result.ok ? .tool : .error, trimmed(result.text, limit: 1_200))

        do {
            try await socket?.sendFunctionOutput(callID: call.callID, output: result.jsonString)
            state = .listening
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func flushAssistantDraft(fallback: String?) {
        let text = assistantDraft.isEmpty ? (fallback ?? "") : assistantDraft
        guard text.isEmpty == false else { return }
        assistantDraft = ""
        append(.assistant, text)
    }

    private func append(_ kind: AgentLogEntry.Kind, _ message: String) {
        logs.append(AgentLogEntry(kind: kind, message: message))
        if logs.count > 160 {
            logs.removeFirst(logs.count - 160)
        }
    }

    private func fail(_ message: String) {
        state = .error(message)
        append(.error, message)
    }

    private func stableSafetyIdentifier() -> String {
        let key = "samanthaMacSafetyIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = "samantha-mac-\(UUID().uuidString)"
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func functionCall(from event: [String: Any]) -> PendingFunctionCall? {
        guard let callID = event["call_id"] as? String,
              let name = event["name"] as? String else { return nil }
        return PendingFunctionCall(
            callID: callID,
            name: name,
            argumentsJSON: event["arguments"] as? String ?? "{}"
        )
    }

    private func functionCall(fromOutputItem item: [String: Any]) -> PendingFunctionCall? {
        guard item["type"] as? String == "function_call",
              let callID = item["call_id"] as? String,
              let name = item["name"] as? String else { return nil }
        return PendingFunctionCall(
            callID: callID,
            name: name,
            argumentsJSON: item["arguments"] as? String ?? "{}"
        )
    }

    private func functionCalls(fromResponseDoneEvent event: [String: Any]) -> [PendingFunctionCall] {
        guard let response = event["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else { return [] }
        return output.compactMap(functionCall(fromOutputItem:))
    }

    private func trimmed(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n..."
    }

    private static func errorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let code = error["code"] as? String { return code }
        }
        if let message = event["message"] as? String { return message }
        return "Realtime session error."
    }

    private static let instructions = """
    # Role & Objective
    You are Samantha Mac, a concise voice assistant that can control this Mac through local tools.
    The user speaks naturally. Respond with short spoken updates and execute tools only when they help.

    # Tool Availability
    Available tools are exactly: shell_exec, open_app, read_screen, list_apps.
    Do not mention or pretend to use unavailable tools.
    Only say an action is complete after the relevant tool output confirms it.

    # Local Action Rules
    - Use read_screen only when the current visible UI is needed.
    - Use open_app to launch apps.
    - Use shell_exec for local commands. Read-only commands may run directly. Mutating or risky commands may require user approval.
    - If approval is needed, briefly tell the user what needs approval and wait.

    # Safety
    Never delete, overwrite, send, purchase, post, or install without explicit approval.
    If the user asks for something ambiguous, ask one short clarification.

    # Voice Style
    Speak in the user's language.
    Be direct and brief.
    Avoid filler. Avoid long explanations during tool use.
    """
}
