import Foundation
import GuesliCore

private enum RemovedCanaryQwenMigration {
    static let backend = "canary"
    static let model = "phequals/canary-qwen-2.5b-coreml-int8"
    static let fallback = BackendOption.gigaAMV3Russian

    static func matches(backend: String, model: String) -> Bool {
        backend == Self.backend || model == Self.model
    }

    static func cacheDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/guesli/models", isDirectory: true)
            .appendingPathComponent("canary-qwen-2.5b-coreml-int8", isDirectory: true)
    }
}

private enum RemovedGigaAMBackendMigration {
    static let fallback = BackendOption.gigaAMV3Russian
    static let legacyModels: Set<String> = [
        "huggingfinger0/gigaam-v3-coreml",
        "kruatech/gigaam-v3-mlx",
    ]

    static func matches(backend: String, model: String) -> Bool {
        backend == "sherpa_gigaam_rnnt"
            || (backend == "gigaam_v3" && legacyModels.contains(model))
    }
}

private enum RemovedLegacyASRMigration {
    static let fallback = BackendOption.parakeetMultilingual
    static let removedBackends: Set<String> = [
        "parakeet-unified",
        "whisper",
        "qwen",
        "cohere",
        "sensevoice",
    ]
    static let removedFluidAudioModels: Set<String> = [
        "FluidInference/parakeet-tdt-0.6b-v2-coreml",
    ]

    static func matches(backend: String, model: String) -> Bool {
        removedBackends.contains(backend)
            || (backend == "fluidaudio" && removedFluidAudioModels.contains(model))
    }
}

final class ConfigStore {
    private let configURL: URL
    private let supportURL: URL
    private let removedCanaryQwenModelCacheURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        supportURL: URL = AppIdentity.supportDirectoryURL,
        removedCanaryQwenModelCacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.supportURL = supportURL.standardizedFileURL
        self.removedCanaryQwenModelCacheURL = removedCanaryQwenModelCacheURL
            ?? RemovedCanaryQwenMigration.cacheDirectory(fileManager: fileManager)
        self.fileManager = fileManager
        self.configURL = supportURL.appendingPathComponent("config.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppConfig {
        ensureDirectory()
        var config: AppConfig
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? decoder.decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }

        let didMigrateRemovedCanaryQwen = migrateRemovedCanaryQwenSelection(in: &config)
        let didMigrateRemovedGigaAM = migrateRemovedGigaAMSelection(in: &config)
        let didMigrateRemovedLegacyASR = migrateRemovedLegacyASRSelection(in: &config)
        if didMigrateRemovedCanaryQwen
            || didMigrateRemovedGigaAM
            || didMigrateRemovedLegacyASR {
            save(config)
        }
        if didMigrateRemovedCanaryQwen,
           fileManager.fileExists(atPath: removedCanaryQwenModelCacheURL.path) {
            DiagnosticsLog.write(
                "[config-store] preserved removed Canary Qwen model cache at \(removedCanaryQwenModelCacheURL.path)"
            )
        }
        return config
    }

    func save(_ config: AppConfig) {
        ensureDirectory()
        guard let data = try? encoder.encode(config) else { return }
        do {
            try data.write(to: configURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configURL.path
            )
        } catch {
            fputs("[config-store] failed to save config: \(error)\n", stderr)
        }
    }

    func configPath() -> URL {
        configURL
    }

    func supportDirectory() -> URL {
        supportURL
    }

    private func ensureDirectory() {
        GuesliPaths.preconditionSafeForTestWrite(configURL)
        try? fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateRemovedCanaryQwenSelection(in config: inout AppConfig) -> Bool {
        var didMigrate = false

        func migrate(_ field: String, backend: inout String, model: inout String) {
            guard RemovedCanaryQwenMigration.matches(backend: backend, model: model) else { return }
            backend = RemovedCanaryQwenMigration.fallback.backend
            model = RemovedCanaryQwenMigration.fallback.model
            didMigrate = true
            DiagnosticsLog.write("[config-store] migrated removed Canary Qwen \(field) backend to \(RemovedCanaryQwenMigration.fallback.label)")
        }

        migrate("dictation", backend: &config.sttBackend, model: &config.sttModel)
        migrate("meeting", backend: &config.meetingTranscriptionBackend, model: &config.meetingTranscriptionModel)
        return didMigrate
    }

    private func migrateRemovedGigaAMSelection(in config: inout AppConfig) -> Bool {
        var didMigrate = false

        func migrate(_ field: String, backend: inout String, model: inout String) {
            guard RemovedGigaAMBackendMigration.matches(backend: backend, model: model) else { return }
            backend = RemovedGigaAMBackendMigration.fallback.backend
            model = RemovedGigaAMBackendMigration.fallback.model
            didMigrate = true
            DiagnosticsLog.write("[config-store] migrated removed GigaAM \(field) backend to \(RemovedGigaAMBackendMigration.fallback.label)")
        }

        migrate("dictation", backend: &config.sttBackend, model: &config.sttModel)
        migrate("meeting", backend: &config.meetingTranscriptionBackend, model: &config.meetingTranscriptionModel)
        return didMigrate
    }

    private func migrateRemovedLegacyASRSelection(in config: inout AppConfig) -> Bool {
        var didMigrate = false

        func migrate(_ field: String, backend: inout String, model: inout String) {
            guard RemovedLegacyASRMigration.matches(backend: backend, model: model) else { return }
            backend = RemovedLegacyASRMigration.fallback.backend
            model = RemovedLegacyASRMigration.fallback.model
            didMigrate = true
            DiagnosticsLog.write(
                "[config-store] migrated removed legacy \(field) ASR backend to \(RemovedLegacyASRMigration.fallback.label)"
            )
        }

        migrate("dictation", backend: &config.sttBackend, model: &config.sttModel)
        migrate("meeting", backend: &config.meetingTranscriptionBackend, model: &config.meetingTranscriptionModel)
        return didMigrate
    }

}
