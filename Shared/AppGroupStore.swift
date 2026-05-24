import Foundation

enum AppGroupStore {
    static let identifier = "group.com.alexmitre.samanthakey"
    static let selectedLanguageKey = "selectedOutputLanguage"
    static let pendingTextKey = "pendingTranslatedText"
    static let sessionIDKey = "handoffSessionID"
    static let statusKey = "handoffStatus"
    static let updatedAtKey = "handoffUpdatedAt"
    static let hasEntitlementKey = "hasActiveEntitlement"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var selectedLanguage: AppLanguage {
        get { AppLanguage.resolved(from: defaults.string(forKey: selectedLanguageKey)) }
        set { defaults.set(newValue.rawValue, forKey: selectedLanguageKey) }
    }

    static func setEntitlementActive(_ active: Bool) {
        defaults.set(active, forKey: hasEntitlementKey)
    }

    static var hasEntitlement: Bool {
        defaults.bool(forKey: hasEntitlementKey)
    }

    static func startHandoff(language: AppLanguage) -> String {
        let sessionID = UUID().uuidString
        selectedLanguage = language
        defaults.set(sessionID, forKey: sessionIDKey)
        defaults.set(HandoffStatus.requested.rawValue, forKey: statusKey)
        defaults.removeObject(forKey: pendingTextKey)
        touch()
        return sessionID
    }

    static func publish(text: String, status: HandoffStatus) {
        defaults.set(text, forKey: pendingTextKey)
        defaults.set(status.rawValue, forKey: statusKey)
        touch()
    }

    static func clearPublishedText() {
        defaults.removeObject(forKey: pendingTextKey)
        defaults.set(HandoffStatus.idle.rawValue, forKey: statusKey)
        touch()
    }

    static var pendingText: String {
        defaults.string(forKey: pendingTextKey) ?? ""
    }

    static var status: HandoffStatus {
        HandoffStatus(rawValue: defaults.string(forKey: statusKey) ?? "") ?? .idle
    }

    static var updatedAt: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: updatedAtKey))
    }

    private static func touch() {
        defaults.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
        defaults.synchronize()
    }
}

enum HandoffStatus: String, Codable {
    case idle
    case requested
    case recording
    case ready
    case error
}
