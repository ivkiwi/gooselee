import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Legacy installation preservation", .serialized, .muesliHermeticSupport)
struct LegacyInstallationPreservationTests {
    @Test("config round-trip and migrations preserve user-owned files and settings")
    func configAndFilesSurviveRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-installation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let support = root.appendingPathComponent("Guesli", isDirectory: true)
        let legacy = root.appendingPathComponent("Muesli", isDirectory: true)
        let modelCache = root.appendingPathComponent("models/canary-qwen", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelCache, withIntermediateDirectories: true)

        let credentialURL = support.appendingPathComponent("chatgpt-auth.json")
        let recordingURL = support.appendingPathComponent("meeting.wav")
        let modelURL = modelCache.appendingPathComponent("weights.bin")
        let credentialData = Data("fixture-credential-data".utf8)
        let recordingData = Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03, 0x04])
        let modelData = Data("fixture-model-data".utf8)
        try credentialData.write(to: credentialURL)
        try recordingData.write(to: recordingURL)
        try modelData.write(to: modelURL)

        let store = ConfigStore(
            supportURL: support,
            legacySupportURL: legacy,
            removedCanaryQwenModelCacheURL: modelCache
        )
        let meetingTemplate = CustomMeetingTemplate(
            id: "fixture-template",
            name: "Мой шаблон",
            prompt: "Сохрани решения и ручные заметки",
            icon: "doc.text"
        )
        let cleanupPrompt = CustomTranscriptCleanupPrompt(
            id: "fixture-cleanup",
            name: "Технический текст",
            prompt: "Не меняй отрицания и идентификаторы"
        )
        var config = AppConfig()
        config.sttBackend = BackendOption.nemotron35Multilingual.backend
        config.sttModel = BackendOption.nemotron35Multilingual.model
        config.meetingTranscriptionBackend = BackendOption.parakeetMultilingual.backend
        config.meetingTranscriptionModel = BackendOption.parakeetMultilingual.model
        config.nemotron35Language = Nemotron35Language.hindi.rawValue
        config.customMeetingTemplates = [meetingTemplate]
        config.defaultMeetingTemplateID = meetingTemplate.id
        config.enablePostProcessor = true
        config.transcriptCleanupProvider = TranscriptCleanupProviderOption.chatGPT.rawValue
        config.enableMeetingTranscriptCleanup = true
        config.meetingTranscriptCleanupProvider = MeetingTranscriptCleanupProviderOption.chatGPT.rawValue
        config.customTranscriptCleanupPrompts = [cleanupPrompt]
        config.activeTranscriptCleanupPromptId = cleanupPrompt.id
        config.customWords = [CustomWord(word: "PostHog", replacement: "PostHog")]
        config.enableComputerUsePlanner = true
        config.enableComputerUseHotkey = true
        config.iCloudSyncEnabled = true
        config.meetingRecordingSavePolicy = .always
        store.save(config)

        let firstLoad = store.load()
        store.save(firstLoad)
        let secondLoad = store.load()

        #expect(secondLoad.sttBackend == config.sttBackend)
        #expect(secondLoad.sttModel == config.sttModel)
        #expect(secondLoad.meetingTranscriptionBackend == config.meetingTranscriptionBackend)
        #expect(secondLoad.meetingTranscriptionModel == config.meetingTranscriptionModel)
        #expect(secondLoad.nemotron35Language == config.nemotron35Language)
        #expect(secondLoad.customMeetingTemplates == [meetingTemplate])
        #expect(secondLoad.defaultMeetingTemplateID == meetingTemplate.id)
        #expect(secondLoad.customTranscriptCleanupPrompts == [cleanupPrompt])
        #expect(secondLoad.activeTranscriptCleanupPromptId == cleanupPrompt.id)
        #expect(secondLoad.enablePostProcessor)
        #expect(secondLoad.enableMeetingTranscriptCleanup)
        #expect(secondLoad.enableComputerUsePlanner)
        #expect(secondLoad.enableComputerUseHotkey)
        #expect(secondLoad.iCloudSyncEnabled)
        #expect(secondLoad.meetingRecordingSavePolicy == .always)
        #expect(try Data(contentsOf: credentialURL) == credentialData)
        #expect(try Data(contentsOf: recordingURL) == recordingData)
        #expect(try Data(contentsOf: modelURL) == modelData)
    }

    @Test("repeated database migration preserves meetings, traces, and recordings")
    func databaseMigrationIsIdempotentAndNonDestructive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-database-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let databaseURL = root.appendingPathComponent("muesli.db")
        let micURL = root.appendingPathComponent("mic.wav")
        let systemURL = root.appendingPathComponent("system.wav")
        let micData = Data([0x01, 0x02, 0x03])
        let systemData = Data([0x04, 0x05, 0x06])
        try micData.write(to: micURL)
        try systemData.write(to: systemURL)

        let store = DictationStore(databaseURL: databaseURL)
        try store.migrateIfNeeded()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let dictationID = try store.insertDictation(
            text: "Старый текст диктовки",
            durationSeconds: 3,
            appContext: "Fixture",
            startedAt: now,
            endedAt: now.addingTimeInterval(3)
        )
        let traceEvent = ComputerUseTraceEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: "result",
            title: "Legacy trace",
            body: "Read-only history",
            status: "completed",
            step: 1,
            timestamp: "2026-01-01T00:00:00Z"
        )
        try store.insertComputerUseTrace(
            dictationID: dictationID,
            finalStatus: "completed",
            finalMessage: "Legacy result",
            events: [traceEvent]
        )
        let meetingID = try store.insertMeeting(
            title: "Старая встреча",
            calendarEventID: "fixture-calendar-event",
            startTime: now,
            endTime: now.addingTimeInterval(60),
            rawTranscript: "Очищенная расшифровка",
            rawOriginalTranscript: "Исходная расшифровка",
            formattedNotes: "## Решения\n- Ничего не потерять",
            micAudioPath: micURL.path,
            systemAudioPath: systemURL.path,
            savedRecordingPath: micURL.path,
            selectedTemplateID: "fixture-template",
            selectedTemplateName: "Мой шаблон",
            selectedTemplateKind: .custom,
            selectedTemplatePrompt: "Сохрани всё"
        )
        try store.updateMeetingManualNotes(id: meetingID, manualNotes: "Ручная заметка")

        try store.migrateIfNeeded()
        try store.migrateIfNeeded()

        let dictation = try #require(try store.dictation(id: dictationID))
        let meeting = try #require(try store.meeting(id: meetingID))
        #expect(dictation.rawText == "Старый текст диктовки")
        #expect(dictation.computerUseTrace?.finalMessage == "Legacy result")
        #expect(dictation.computerUseTrace?.events == [traceEvent])
        #expect(meeting.rawTranscript == "Очищенная расшифровка")
        #expect(meeting.rawOriginalTranscript == "Исходная расшифровка")
        #expect(meeting.formattedNotes == "## Решения\n- Ничего не потерять")
        #expect(meeting.manualNotes == "Ручная заметка")
        #expect(meeting.selectedTemplatePrompt == "Сохрани всё")
        #expect(meeting.micAudioPath == micURL.path)
        #expect(meeting.systemAudioPath == systemURL.path)
        #expect(try Data(contentsOf: micURL) == micData)
        #expect(try Data(contentsOf: systemURL) == systemData)
    }
}
