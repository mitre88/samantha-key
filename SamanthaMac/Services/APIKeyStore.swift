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
        guard let key = load(), key.count > 14 else { return "" }
        return "\(key.prefix(7))...\(key.suffix(4))"
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
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
