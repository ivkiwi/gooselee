import Foundation
import GuesliCore
import Testing

@Suite("Guesli identity", .guesliHermeticSupport)
struct GuesliIdentityTests {
    @Test("core defaults use the Guesli support directory")
    func coreDefaultsUseGuesliSupportDirectory() {
        let supportURL = GuesliPaths.defaultSupportDirectoryURL()
        let databaseURL = GuesliPaths.defaultDatabaseURL()

        #expect(supportURL.lastPathComponent == "Guesli")
        #expect(databaseURL.deletingLastPathComponent().lastPathComponent == "Guesli")
        #expect(databaseURL.lastPathComponent == "guesli.db")
    }

    @Test("historical database filename migrates without dropping SQLite sidecars")
    func historicalDatabaseFilenameMigrates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guesli-database-name-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let historicalDatabase = root.appendingPathComponent("muesli.db")
        for suffix in ["", "-wal", "-shm"] {
            try Data("database\(suffix)".utf8)
                .write(to: URL(fileURLWithPath: historicalDatabase.path + suffix))
        }

        let migrated = try GuesliPaths.migrateHistoricalDatabaseNameIfNeeded(supportDirectory: root)

        #expect(migrated.lastPathComponent == "guesli.db")
        for suffix in ["", "-wal", "-shm"] {
            #expect(FileManager.default.fileExists(atPath: migrated.path + suffix))
            #expect(!FileManager.default.fileExists(atPath: historicalDatabase.path + suffix))
        }
    }

    @Test("historical model cache directory migrates to Guesli")
    func historicalModelCacheDirectoryMigrates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guesli-cache-name-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let historical = home.appendingPathComponent(".cache/muesli", isDirectory: true)
        try FileManager.default.createDirectory(at: historical, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: historical.appendingPathComponent("model.bin"))

        try GuesliPaths.migrateHistoricalCacheDirectoryIfNeeded(homeDirectory: home)

        let current = home.appendingPathComponent(".cache/guesli", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("model.bin").path))
        #expect(!FileManager.default.fileExists(atPath: historical.path))
    }
}
