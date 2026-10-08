import Foundation

final class OpenAIRealtimeSocket: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let safetyIdentifier: String
    private let onEvent: @MainActor @Sendable (String) -> Void
    private let onError: @MainActor @Sendable (String) -> Void
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var task: URLSessionWebSocketTask?
    private var isClosed = false
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var updateContinuation: CheckedContinuation<Void, Error>?
    private let sendQueue = RealtimeSocketSendQueue()

    init(
        apiKey: String,
        model: String = "gpt-realtime-2",
        safetyIdentifier: String,
        onEvent: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.apiKey = apiKey
        self.model = model
        self.safetyIdentifier = safetyIdentifier
        self.onEvent = onEvent
        self.onError = onError
        super.init()
    }

    func connect() async throws {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let socket = session.webSocketTask(with: request)
        task = socket
        try await withCheckedThrowingContinuation { continuation in
            openContinuation = continuation
            socket.resume()
            receiveNext()
        }
    }

    func configureSession(instructions: String) async throws {
        let payload: [String: Any] = [
            "type": "session.update",
            "event_id": "samantha_mac_session_update",
            "session": [
                "type": "realtime",
                "model": model,
                "instructions": instructions,
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": NSDecimalNumber(string: "0.28"),
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 700,
                            "create_response": true,
                            "interrupt_response": true
                        ],
                        "transcription": [
                            "model": "gpt-4o-mini-transcribe"
                        ]
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "voice": "marin"
                    ]
                ],
                "tools": LocalToolRouter.toolSchemas,
                "tool_choice": "auto"
            ]
        ]

        let text = try encodeObject(payload)
        try await withCheckedThrowingContinuation { continuation in
            updateContinuation = continuation
            Task { [weak self, text] in
                do {
                    try await self?.send(text)
                } catch {
                    self?.resumeSessionUpdateWait(with: .failure(error))
                }
            }
        }
    }

    func sendAudio(_ data: Data) async throws {
        try await sendObject([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
    }

    func enqueueAudio(_ data: Data) throws {
        guard isClosed == false, let task else { throw RealtimeSocketError.closed }
        let text = try encodeObject([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
        let onError = onError
        Task {
            await sendQueue.send(text, task: task, onError: onError)
        }
    }

    func finishTurn() async throws {
        try await sendObject(["type": "input_audio_buffer.commit"])
        try await sendObject(["type": "response.create"])
    }

    func sendFunctionOutput(callID: String, output: String) async throws {
        try await sendObject([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": output
            ]
        ])
        try await sendObject(["type": "response.create"])
    }

    func close() {
        isClosed = true
        openContinuation?.resume(throwing: RealtimeSocketError.closed)
        openContinuation = nil
        updateContinuation?.resume(throwing: RealtimeSocketError.closed)
        updateContinuation = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        openContinuation?.resume()
        openContinuation = nil
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Realtime socket closed."
        openContinuation?.resume(throwing: RealtimeSocketError.closed)
        openContinuation = nil
        updateContinuation?.resume(throwing: RealtimeSocketError.server(reasonText))
        updateContinuation = nil
    }

    private func sendObject(_ object: [String: Any]) async throws {
        let text = try encodeObject(object)
        try await send(text)
    }

    private func encodeObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func send(_ text: String) async throws {
        guard isClosed == false, let task else { throw RealtimeSocketError.closed }
        try await sendQueue.send(text, task: task)
    }

    private func receiveNext() {
        guard isClosed == false, let task else { return }
        task.receive { [weak self] result in
            guard let self, self.isClosed == false else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleSocketEvent(text)
                    Task { @MainActor in self.onEvent(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleSocketEvent(text)
                        Task { @MainActor in self.onEvent(text) }
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure(let error):
                self.openContinuation?.resume(throwing: error)
                self.openContinuation = nil
                self.updateContinuation?.resume(throwing: error)
                self.updateContinuation = nil
                Task { @MainActor in self.onError(error.localizedDescription) }
            }
        }
    }

    private func resumeSessionUpdateWait(with result: Result<Void, Error>) {
        guard let updateContinuation else { return }
        self.updateContinuation = nil
        switch result {
        case .success:
            updateContinuation.resume()
        case .failure(let error):
            updateContinuation.resume(throwing: error)
        }
    }

    private func waitForSessionUpdate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            updateContinuation = continuation
        }
    }

    private func handleSocketEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        if type == "session.updated" {
            resumeSessionUpdateWait(with: .success(()))
        } else if type == "error" {
            let message = Self.errorMessage(from: event)
            resumeSessionUpdateWait(with: .failure(RealtimeSocketError.server(message)))
        }
    }

    private static func errorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String, message.isEmpty == false { return message }
            if let code = error["code"] as? String, code.isEmpty == false { return code }
        }
        if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8),
           text.isEmpty == false {
            return text
        }
        return "Realtime API error."
    }
}

private actor RealtimeSocketSendQueue {
    func send(_ text: String, task: URLSessionWebSocketTask) async throws {
        try await task.send(.string(text))
    }

    func send(
        _ text: String,
        task: URLSessionWebSocketTask,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        do {
            try await send(text, task: task)
        } catch {
            await onError(error.localizedDescription)
        }
    }
}

private enum RealtimeSocketError: LocalizedError {
    case closed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .closed:
            return "Realtime socket closed before the session was ready."
        case .server(let message):
            return message
        }
    }
}
