import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = support.appendingPathComponent("psybeam", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("psybeam.sqlite").path
            dbQueue = try DatabaseQueue(path: path)
            try Self.runMigrations(dbQueue)
            AppLogger.shared.info("database opened at \(path)", category: .persistence)
        } catch {
            fatalError("Database init failed: \(error)")
        }
    }

    init(inMemoryName: String) throws {
        dbQueue = try DatabaseQueue(named: inMemoryName)
        try Self.runMigrations(dbQueue)
    }

    private static func runMigrations(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "appPreferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("travelerLang", .text).notNull()
                t.column("autoSuggestLocal", .boolean).notNull().defaults(to: true)
                t.column("applyAutomatically", .boolean).notNull().defaults(to: false)
                t.column("aiConsentGranted", .boolean).notNull().defaults(to: false)
                t.column("consentedAt", .datetime)
                t.column("recentLangs", .text).notNull().defaults(to: "")
            }
        }
        try migrator.migrate(db)
    }

    func preferences() throws -> AppPreferences? {
        try dbQueue.read { db in
            try AppPreferences.fetchOne(db)
        }
    }

    @discardableResult
    func savePreferences(_ preferences: AppPreferences) throws -> AppPreferences {
        try dbQueue.write { db in
            try preferences.saved(db)
        }
    }

    /// Erases all on-device records (App Store 5.1.1(v) account deletion). The
    /// schema is recreated empty so the app keeps working with a clean state.
    func wipe() throws {
        try dbQueue.write { db in
            try AppPreferences.deleteAll(db)
        }
    }
}
