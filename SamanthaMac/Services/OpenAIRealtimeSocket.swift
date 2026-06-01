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
        socket.resume()
        receiveNext()
        try await waitForOpen()
    }

    func configureSession(instructions: String) async throws {
        let updateWait = makeSessionUpdateWaitTask()
        try await sendObject([
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
                            "threshold": 0.5,
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
        ])
        try await updateWait.value
    }

    func sendAudio(_ data: Data) async throws {
        try await sendObject([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
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
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await send(text)
    }

    private func send(_ text: String) async throws {
        guard isClosed == false, let task else { throw RealtimeSocketError.closed }
        try await task.send(.string(text))
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

    private func waitForOpen() async throws {
        try await withCheckedThrowingContinuation { continuation in
            openContinuation = continuation
        }
    }

    private func makeSessionUpdateWaitTask() -> Task<Void, Error> {
        Task { [weak self] in
            try await withCheckedThrowingContinuation { continuation in
                self?.updateContinuation = continuation
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
            return (error["message"] as? String) ?? (error["code"] as? String) ?? "Realtime API error."
        }
        return "Realtime API error."
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
