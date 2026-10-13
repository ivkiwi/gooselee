import Foundation
import GuesliCore
import Testing
@testable import GuesliApp

@Suite("Storage configuration and cancellation", .serialized, .guesliHermeticSupport)
struct StorageConfigAndCancellationTests {
    @Test("Corrupt settings are preserved before defaults can overwrite them")
    func corruptSettingsArePreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        let broken = Data("{ invalid fixture".utf8)
        try broken.write(to: configURL)
        let store = ConfigStore(supportURL: root)
        // save must also be safe when a caller did not load first.
        store.save(AppConfig())
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.json.corrupt-") }
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: backup) == broken)
        #expect(try Data(contentsOf: configURL) != broken)
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Failed corrupt settings backup blocks overwriting the original")
    func failedSettingsBackupBlocksSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blocked-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        let broken = Data("{ invalid fixture".utf8)
        try broken.write(to: configURL)
        let store = ConfigStore(supportURL: root, fileManager: ConfigBackupFailureFileManager())
        _ = store.load()
        store.save(AppConfig())
        #expect(try Data(contentsOf: configURL) == broken)
    }

    @Test("Empty refresh tokens are omitted from both persisted token files")
    func emptyRefreshTokensAreNotPersisted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("empty-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AuthTokenFileStore(primaryURL: root.appendingPathComponent("tokens.json"), logPrefix: "test", logger: { _ in })
        try store.save(["access_token": "fixture", "refresh_token": ""], reason: "test")
        for path in [store.primaryURL, store.backupURL] {
            let data = try Data(contentsOf: path)
            let tokens = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
            #expect(tokens["refresh_token"] == nil)
            #expect(tokens["access_token"] == "fixture")
        }
    }

    @Test("Legacy empty refresh token signs out instead of sending an empty refresh request")
    @MainActor
    func legacyEmptyRefreshTokenRequiresSignIn() async throws {
        let store = AuthTokenFileStore(primaryURL: AppIdentity.supportDirectoryURL.appendingPathComponent("chatgpt-auth.json"), logPrefix: "test", logger: { _ in })
        defer { store.signOut() }
        let legacy: [String: String] = ["access_token": "fixture", "refresh_token": "", "expires_at": "0"]
        try store.save(JSONSerialization.data(withJSONObject: legacy), reason: "test")
        do {
            _ = try await ChatGPTAuthManager.shared.validAccessToken()
            Issue.record("Expired credentials accepted an empty refresh token")
        } catch ChatGPTAuthError.notAuthenticated {
            #expect(!ChatGPTAuthManager.shared.isAuthenticated)
            #expect(store.load() == nil)
        }
    }
}

private final class ConfigBackupFailureFileManager: FileManager {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: "ConfigBackupFailureFileManager", code: 1)
    }
}
