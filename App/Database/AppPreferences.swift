import Foundation
import GRDB

struct AppPreferences: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var travelerLang: String
    var autoSuggestLocal: Bool
    var applyAutomatically: Bool
    var aiConsentGranted: Bool
    var consentedAt: Date?
    var recentLangs: String

    static let databaseTableName = "appPreferences"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let travelerLang = Column(CodingKeys.travelerLang)
        static let autoSuggestLocal = Column(CodingKeys.autoSuggestLocal)
        static let applyAutomatically = Column(CodingKeys.applyAutomatically)
        static let aiConsentGranted = Column(CodingKeys.aiConsentGranted)
        static let consentedAt = Column(CodingKeys.consentedAt)
        static let recentLangs = Column(CodingKeys.recentLangs)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension AppPreferences {
    static func makeDefault(travelerLang: String) -> AppPreferences {
        AppPreferences(
            id: nil,
            travelerLang: travelerLang,
            autoSuggestLocal: true,
            applyAutomatically: false,
            aiConsentGranted: false,
            consentedAt: nil,
            recentLangs: ""
        )
    }
}
