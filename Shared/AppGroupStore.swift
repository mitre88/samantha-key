import Foundation

enum AppGroupStore {
    static let identifier = "group.com.alexmitre.samanthakey"
    static let selectedLanguageKey = "selectedOutputLanguage"
    static let pendingTextKey = "pendingTranslatedText"
    static let sessionIDKey = "handoffSessionID"
    static let statusKey = "handoffStatus"
    static let updatedAtKey = "handoffUpdatedAt"
    static let hasEntitlementKey = "hasActiveEntitlement"
    private static let accessProbeKey = "handoffAccessProbe"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static var isAppGroupAvailable: Bool {
        sharedDefaults != nil
    }

    static var isSharedStateWritable: Bool {
        guard let defaults = sharedDefaults else { return false }
        let marker = UUID().uuidString
        defaults.set(marker, forKey: accessProbeKey)
        defaults.synchronize()
        let canReadBack = defaults.string(forKey: accessProbeKey) == marker
        defaults.removeObject(forKey: accessProbeKey)
        defaults.synchronize()
        return canReadBack
    }

    static var defaults: UserDefaults {
        sharedDefaults ?? .standard
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

    static var currentSessionID: String {
        defaults.string(forKey: sessionIDKey) ?? ""
    }

    static func startHandoff(language: AppLanguage, sessionID: String = UUID().uuidString) -> String {
        selectedLanguage = language
        defaults.set(sessionID, forKey: sessionIDKey)
        defaults.set(HandoffStatus.requested.rawValue, forKey: statusKey)
        defaults.removeObject(forKey: pendingTextKey)
        touch()
        return sessionID
    }

    static func publish(text: String, status: HandoffStatus, sessionID: String? = nil) {
        if let sessionID, sessionID.isEmpty == false {
            defaults.set(sessionID, forKey: sessionIDKey)
        }
        defaults.set(text, forKey: pendingTextKey)
        defaults.set(status.rawValue, forKey: statusKey)
        touch()
    }

    static func clearPublishedText(sessionID: String? = nil) {
        if let sessionID, currentSessionID != sessionID { return }
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

enum KeyboardLocalFeedback {
    static let notificationName = Notification.Name("SamanthaKeyboardLocalFeedback")
    static let textKey = "text"
    static let statusKey = "status"
    static let sessionIDKey = "sessionID"

    static func post(text: String, status: HandoffStatus, sessionID: String? = nil) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                textKey: text,
                statusKey: status.rawValue,
                sessionIDKey: sessionID ?? ""
            ]
        )
    }
}

enum HandoffStatus: String, Codable {
    case idle
    case requested
    case recording
    case ready
    case error
}
