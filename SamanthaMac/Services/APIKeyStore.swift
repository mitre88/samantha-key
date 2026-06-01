import Foundation
import Security

enum APIKeyStore {
    private static let service = "com.alexmitre.samanthamac.openai"
    private static let account = "OPENAI_API_KEY"

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              key.isEmpty == false else { return nil }
        return key
    }

    static func resolvedKey() -> String? {
        if let stored = load() {
            return stored
        }

        if let environmentKey = validatedKey(ProcessInfo.processInfo.environment["OPENAI_API_KEY"]) {
            try? save(environmentKey)
            return environmentKey
        }

        if let configuredKey = loadFromLocalConfiguration() {
            try? save(configuredKey)
            return configuredKey
        }

        return nil
    }

    static func save(_ rawValue: String) throws {
        let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false, key.contains("...") == false else { return }

        let data = Data(key.utf8)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unableToSave(addStatus)
        }
    }

    static var maskedValue: String {
        guard let key = resolvedKey(), key.count > 14 else { return "" }
        return "\(key.prefix(7))...\(key.suffix(4))"
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func loadFromLocalConfiguration() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".config/samantha-key/openai.env"),
            home.appending(path: ".config/samantha-key/.env"),
            home.appending(path: ".config/samantha/openai.env"),
            home.appending(path: ".config/opencode/opencode.jsonc"),
            home.appending(path: ".zshenv"),
            home.appending(path: ".zprofile"),
            home.appending(path: ".zshrc")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path()) {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let key = extractKey(from: text) else { continue }
            return key
        }

        return nil
    }

    private static func extractKey(from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#") == false,
                  trimmed.hasPrefix("//") == false else { continue }

            if trimmed.contains("OPENAI_API_KEY"),
               let value = valueAfterSeparator(in: trimmed),
               let key = validatedKey(value) {
                return key
            }

            if let key = firstOpenAIKey(in: trimmed) {
                return key
            }
        }

        return firstOpenAIKey(in: text)
    }

    private static func valueAfterSeparator(in line: String) -> String? {
        guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { return nil }
        let value = line[line.index(after: separator)...]
        return String(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))
    }

    private static func firstOpenAIKey(in text: String) -> String? {
        let pattern = #"sk-(?:proj-)?[A-Za-z0-9_-]{20,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return validatedKey(String(text[swiftRange]))
    }

    private static func validatedKey(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let key = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))
        guard key.hasPrefix("sk-"), key.count > 24, key.contains("YOUR_") == false else { return nil }
        return key
    }
}

enum KeychainError: LocalizedError {
    case unableToSave(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToSave(let status): "Could not save the API key in Keychain. OSStatus \(status)."
        }
    }
}
