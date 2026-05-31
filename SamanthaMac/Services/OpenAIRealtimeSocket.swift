import Foundation

final class OpenAIRealtimeSocket: @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let safetyIdentifier: String
    private let onEvent: @MainActor @Sendable (String) -> Void
    private let onError: @MainActor @Sendable (String) -> Void
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var isClosed = false

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
    }

    func configureSession(instructions: String) async throws {
        try await sendObject([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": model,
                "instructions": instructions,
                "output_modalities": ["audio", "text"],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "turn_detection": [
                            "type": "semantic_vad"
                        ]
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm"
                        ],
                        "voice": "marin"
                    ]
                ],
                "tools": LocalToolRouter.toolSchemas,
                "tool_choice": "auto"
            ]
        ])
    }

    func sendAudio(_ data: Data) async throws {
        try await sendObject([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
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
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendObject(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await send(text)
    }

    private func send(_ text: String) async throws {
        guard isClosed == false, let task else { return }
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
                    Task { @MainActor in self.onEvent(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        Task { @MainActor in self.onEvent(text) }
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure(let error):
                Task { @MainActor in self.onError(error.localizedDescription) }
            }
        }
    }
}
