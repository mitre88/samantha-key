import Foundation

struct RealtimeTokenResponse: Decodable {
    struct ClientSecret: Decodable {
        let value: String
        let expiresAt: Int?

        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
        }
    }

    let value: String?
    let clientSecret: ClientSecret?
    let callEndpoint: URL?
    let webRTCEndpoint: URL?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case value
        case clientSecret = "client_secret"
        case callEndpoint = "call_endpoint"
        case webRTCEndpoint = "webrtc_call_endpoint"
        case model
    }

    var token: String? {
        value ?? clientSecret?.value
    }
}

struct TextTranslationResponse: Decodable {
    let translatedText: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}

final class BackendClient {
    private let baseURL: URL
    private let urlSession: URLSession

    init(
        baseURL: URL = URL(string: Bundle.main.object(forInfoDictionaryKey: "SAMANTHA_KEY_SUPABASE_FUNCTIONS_URL") as? String ?? "https://bkihgttwlfddnykagyvz.supabase.co/functions/v1")!,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func realtimeToken(entitlement: EntitlementPayload, outputLanguage: AppLanguage) async throws -> RealtimeTokenResponse {
        let url = baseURL.appending(path: "samantha-key-realtime-token")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RealtimeTokenRequest(
                entitlement: entitlement,
                outputLanguage: outputLanguage.realtimeLabel,
                outputLanguageCode: outputLanguage.realtimeTranslationCode
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(Self.serverErrorMessage(from: data, statusCode: http.statusCode))
        }
        return try JSONDecoder().decode(RealtimeTokenResponse.self, from: data)
    }

    func translateText(entitlement: EntitlementPayload, text: String, outputLanguage: AppLanguage) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let url = baseURL.appending(path: "samantha-key-text-translate")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TextTranslationRequest(
                entitlement: entitlement,
                text: String(trimmed.prefix(2_000)),
                outputLanguage: outputLanguage.realtimeLabel,
                outputLanguageCode: outputLanguage.realtimeTranslationCode
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(Self.serverErrorMessage(from: data, statusCode: http.statusCode))
        }

        let decoded = try JSONDecoder().decode(TextTranslationResponse.self, from: data)
        return decoded.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serverErrorMessage(from data: Data, statusCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            if envelope.error == "openai_token_failed",
               let message = envelope.detail?.error?.message {
                return "OpenAI voice token failed: \(message)"
            }
            if let message = envelope.detail?.error?.message { return message }
            if let error = envelope.error { return error.replacingOccurrences(of: "_", with: " ") }
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }
}

private struct RealtimeTokenRequest: Encodable {
    let entitlement: EntitlementPayload
    let outputLanguage: String
    let outputLanguageCode: String
}

private struct TextTranslationRequest: Encodable {
    let entitlement: EntitlementPayload
    let text: String
    let outputLanguage: String
    let outputLanguageCode: String
}

private struct ServerErrorEnvelope: Decodable {
    let error: String?
    let detail: OpenAIErrorEnvelope?
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorMessage?
}

private struct OpenAIErrorMessage: Decodable {
    let message: String?
    let type: String?
    let code: String?
}

enum BackendError: LocalizedError {
    case invalidResponse
    case missingEntitlement
    case missingRealtimeToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server response was invalid."
        case .missingEntitlement: "Start the free trial to unlock real-time translation."
        case .missingRealtimeToken: "The server did not return a usable voice token."
        case .server(let message): message
        }
    }
}
