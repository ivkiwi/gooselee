import Testing
import Foundation
import GuesliCore
@testable import GuesliApp

@Suite("ConfigStore", .serialized, .guesliHermeticSupport)
struct ConfigStoreTests {

    private func makeStore() -> ConfigStore {
        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-store-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library/Application Support/Guesli", isDirectory: true)
        return ConfigStore(supportURL: supportURL)
    }

    @Test("load returns a valid config")
    func loadReturnsConfig() {
        let store = makeStore()
        let config = store.load()
        // Hotkey may have been customized by user — just verify it loaded
        #expect(HotkeyConfig.label(for: config.dictationHotkey.keyCode) != nil)
        #expect(!config.sttBackend.isEmpty)
        #expect(config.resolvedChatGPTDictationCleanupModel == AppConfig.defaultChatGPTDictationCleanupModel)
        #expect(config.resolvedChatGPTMeetingCleanupModel == AppConfig.defaultChatGPTMeetingCleanupModel)
    }

    @Test("save and load round-trip")
    func saveLoadRoundTrip() {
        let store = makeStore()
        let original = store.load()

        var config = original
        config.openAIAPIKey = "sk-test-roundtrip"
        config.openAIModel = "gpt-5.4-pro"
        config.openRouterAPIKey = "sk-or-test-roundtrip"
        config.openRouterModel = "nvidia/nemotron-3-super-120b-a12b:free"
        config.chatGPTDictationCleanupModel = "gpt-dictation-roundtrip"
        config.chatGPTMeetingCleanupModel = "gpt-meeting-roundtrip"
        config.meetingSummaryBackend = "openrouter"
        store.save(config)

        let loaded = store.load()
        #expect(loaded.openAIAPIKey == "sk-test-roundtrip")
        #expect(loaded.openAIModel == "gpt-5.4-pro")
        #expect(loaded.openRouterAPIKey == "sk-or-test-roundtrip")
        #expect(loaded.openRouterModel == "nvidia/nemotron-3-super-120b-a12b:free")
        #expect(loaded.chatGPTDictationCleanupModel == "gpt-dictation-roundtrip")
        #expect(loaded.chatGPTMeetingCleanupModel == "gpt-meeting-roundtrip")
        #expect(loaded.meetingSummaryBackend == "openrouter")

        // Restore original
        store.save(original)
    }

    @Test("load migrates removed Canary Qwen backend without deleting cache")
    func loadMigratesRemovedCanaryQwenBackendWithoutDeletingCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-qwen-migration-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let supportURL = root.appendingPathComponent("Guesli", isDirectory: true)
        let cacheURL = root
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("canary-qwen-2.5b-coreml-int8", isDirectory: true)

        let store = ConfigStore(
            supportURL: supportURL,
            removedCanaryQwenModelCacheURL: cacheURL
        )
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data("stale model".utf8)
            .write(to: cacheURL.appendingPathComponent("canary_embeddings.bin"))
        try Data(
            """
            {
              "stt_backend": "canary",
              "stt_model": "phequals/canary-qwen-2.5b-coreml-int8",
              "meeting_transcription_backend": "canary",
              "meeting_transcription_model": "phequals/canary-qwen-2.5b-coreml-int8"
            }
            """.utf8
        ).write(to: store.configPath())

        let loaded = store.load()

        #expect(loaded.sttBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(loaded.sttModel == BackendOption.gigaAMV3Russian.model)
        #expect(loaded.meetingTranscriptionBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(loaded.meetingTranscriptionModel == BackendOption.gigaAMV3Russian.model)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(
            try Data(contentsOf: cacheURL.appendingPathComponent("canary_embeddings.bin"))
                == Data("stale model".utf8)
        )

        let saved = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: store.configPath()))
        #expect(saved.sttBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(saved.sttModel == BackendOption.gigaAMV3Russian.model)
        #expect(saved.meetingTranscriptionBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(saved.meetingTranscriptionModel == BackendOption.gigaAMV3Russian.model)
    }

    @Test("load migrates removed CoreML and Sherpa GigaAM backends")
    func loadMigratesRemovedGigaAMBackends() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gigaam-backend-migration-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let supportURL = root.appendingPathComponent("Guesli", isDirectory: true)
        let store = ConfigStore(
            supportURL: supportURL,
        )
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try Data(
            """
            {
              "stt_backend": "gigaam_v3",
              "stt_model": "huggingfinger0/gigaam-v3-coreml",
              "meeting_transcription_backend": "sherpa_gigaam_rnnt",
              "meeting_transcription_model": "istupakov/gigaam-v3-rnnt"
            }
            """.utf8
        ).write(to: store.configPath())

        let loaded = store.load()

        #expect(loaded.sttBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(loaded.sttModel == BackendOption.gigaAMV3Russian.model)
        #expect(loaded.meetingTranscriptionBackend == BackendOption.gigaAMV3Russian.backend)
        #expect(loaded.meetingTranscriptionModel == BackendOption.gigaAMV3Russian.model)

        let saved = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: store.configPath()))
        #expect(saved.sttModel == BackendOption.gigaAMV3Russian.model)
        #expect(saved.meetingTranscriptionModel == BackendOption.gigaAMV3Russian.model)
    }

    @Test("load migrates retired ASR selections to multilingual Parakeet")
    func loadMigratesRetiredASRSelections() throws {
        let retiredSelections = [
            ("parakeet-unified", "FluidInference/parakeet-unified-en-0.6b-coreml"),
            ("fluidaudio", "FluidInference/parakeet-tdt-0.6b-v2-coreml"),
            ("whisper", "large-v3-v20240930_626MB"),
            ("qwen", "FluidInference/qwen3-asr-0.6b-coreml"),
            ("cohere", "phequals/cohere-transcribe-coreml-mixed-precision"),
            ("sensevoice", "FluidInference/sensevoice-small-coreml"),
        ]

        for (index, selection) in retiredSelections.enumerated() {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("retired-asr-migration-test-\(index)-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let supportURL = root.appendingPathComponent("Guesli", isDirectory: true)
            let store = ConfigStore(
                supportURL: supportURL,
            )
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let payload: [String: String] = [
                "stt_backend": selection.0,
                "stt_model": selection.1,
                "meeting_transcription_backend": selection.0,
                "meeting_transcription_model": selection.1,
            ]
            try JSONEncoder().encode(payload).write(to: store.configPath())

            let loaded = store.load()

            #expect(loaded.sttBackend == BackendOption.parakeetMultilingual.backend)
            #expect(loaded.sttModel == BackendOption.parakeetMultilingual.model)
            #expect(loaded.meetingTranscriptionBackend == BackendOption.parakeetMultilingual.backend)
            #expect(loaded.meetingTranscriptionModel == BackendOption.parakeetMultilingual.model)

            let saved = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: store.configPath()))
            #expect(saved.sttBackend == BackendOption.parakeetMultilingual.backend)
            #expect(saved.sttModel == BackendOption.parakeetMultilingual.model)
            #expect(saved.meetingTranscriptionBackend == BackendOption.parakeetMultilingual.backend)
            #expect(saved.meetingTranscriptionModel == BackendOption.parakeetMultilingual.model)
        }
    }

    @Test("cleanup prompt selection and custom prompt persist")
    func cleanupPromptSelectionAndCustomPromptPersist() {
        let store = makeStore()
        let prompt = CustomTranscriptCleanupPrompt(id: "custom-cleanup", name: "Brief", prompt: "Clean briefly.")
        var config = AppConfig()
        config.customTranscriptCleanupPrompts = [prompt]
        config.activeTranscriptCleanupPromptId = prompt.id
        config.postProcessorSystemPrompt = prompt.prompt

        store.save(config)

        let loaded = store.load()
        #expect(loaded.customTranscriptCleanupPrompts == [prompt])
        #expect(loaded.activeTranscriptCleanupPromptId == prompt.id)
        #expect(loaded.resolvedTranscriptCleanupSystemPrompt == "Clean briefly.")
    }

    @Test("config path is in Application Support")
    func configPath() {
        let store = makeStore()
        let path = store.configPath().path
        #expect(path.contains("Application Support"))
        #expect(path.hasSuffix("config.json"))
    }

    @Test("saved config uses owner-only file permissions")
    func configPermissions() throws {
        let store = makeStore()
        let original = store.load()

        store.save(original)

        let attributes = try FileManager.default.attributesOfItem(atPath: store.configPath().path)
        let permissions = attributes[.posixPermissions] as? NSNumber

        #expect(permissions?.intValue == 0o600)
    }

}
