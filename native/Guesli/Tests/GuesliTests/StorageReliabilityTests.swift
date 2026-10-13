import Foundation
import SQLite3
import Testing
@testable import GuesliCore

@Suite("Storage reliability", .serialized, .guesliHermeticSupport)
struct StorageReliabilityTests {
    private func makeStore() throws -> DictationStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-reliability-\(UUID().uuidString)")
        let store = DictationStore(databaseURL: root.appendingPathComponent("test.db"))
        try store.migrateIfNeeded()
        return store
    }

    private func execute(_ sql: String, store: DictationStore) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(store.databasePath().path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "StorageReliabilityTests", code: Int(sqlite3_errcode(db)))
        }
    }

    private func count(_ table: String, store: DictationStore) throws -> Int {
        var db: OpaquePointer?
        #expect(sqlite3_open(store.databasePath().path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }

    @Test("Every new database connection waits for competing SQLite writers")
    func busyTimeoutIsConfigured() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.databasePath().deletingLastPathComponent()) }
        for _ in 0..<2 {
            let db = try store.openDatabase()
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(db, "PRAGMA busy_timeout", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) > 0)
        }
    }

    @Test("Late meeting edits cannot restore text, status or audio paths after deletion")
    func deletedMeetingRejectsLateUpdates() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.databasePath().deletingLastPathComponent()) }
        let now = Date()
        let id = try store.createLiveMeeting(title: "Original", calendarEventID: nil, startTime: now)
        try store.deleteMeeting(id: id)
        let updates: [() throws -> Void] = [
            { try store.updateMeeting(id: id, title: "Late", formattedNotes: "Late notes") },
            { try store.updateMeetingNotes(id: id, formattedNotes: "Late notes") },
            { try store.updateMeetingTranscript(id: id, rawTranscript: "Late transcript") },
            { try store.updateMeetingManualNotes(id: id, manualNotes: "Late manual notes") },
            { try store.updateMeetingStatus(id: id, status: .completed) },
            { try store.updateMeetingTitle(id: id, title: "Late title") },
            { try store.updateMeetingSavedRecordingPath(id: id, path: "/tmp/late.wav") },
            { try store.moveMeeting(id: id, toFolder: nil) },
            { try store.updateMeetingSummaryError(id: id, message: "Late error") },
            { try store.updateMeetingSummary(id: id, title: "Late", formattedNotes: "Late notes",
                selectedTemplateID: "auto", selectedTemplateName: "Auto", selectedTemplateKind: .auto, selectedTemplatePrompt: "Prompt") },
            { try store.updateMeetingTranscriptAndSummary(id: id, rawTranscript: "Late", formattedNotes: "Late notes",
                selectedTemplateID: "auto", selectedTemplateName: "Auto", selectedTemplateKind: .auto, selectedTemplatePrompt: "Prompt") },
            { try store.completeLiveMeeting(id: id, title: "Late", calendarEventID: nil, startTime: now, endTime: now,
                rawTranscript: "Late", formattedNotes: "Late notes", micAudioPath: nil, systemAudioPath: nil, savedRecordingPath: nil) }
        ]
        for update in updates {
            do { try update(); Issue.record("Deleted meeting accepted a late update") }
            catch DictationStoreError.meetingNotFound(let missingID) { #expect(missingID == id) }
        }
        #expect(try store.meeting(id: id) == nil)
    }

    @Test("Failed dictation deletion and history clearing preserve computer-use traces")
    func dictationDeletionRollsBack() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.databasePath().deletingLastPathComponent()) }
        let now = Date()
        let id = try store.insertDictation(text: "Original", durationSeconds: 1, startedAt: now, endedAt: now)
        try store.insertComputerUseTrace(dictationID: id, finalStatus: "done", finalMessage: "Original trace", events: [])
        try execute("CREATE TRIGGER reject_dictation_delete BEFORE UPDATE OF deleted_at ON dictations BEGIN SELECT RAISE(ABORT, 'test failure'); END", store: store)
        for deletion in [{ try store.deleteDictation(id: id) }, { try store.clearDictations() }] {
            #expect(throws: (any Error).self) { try deletion() }
            #expect(try count("computer_use_traces", store: store) == 1)
            #expect(try store.dictation(id: id)?.rawText == "Original")
        }
    }

    @Test("Failed meeting history clearing preserves resume snapshots and transcript checkpoints")
    func meetingClearingRollsBack() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.databasePath().deletingLastPathComponent()) }
        let now = Date()
        let id = try store.insertMeeting(title: "Original", calendarEventID: nil, startTime: now, endTime: now,
            rawTranscript: "Original", formattedNotes: "Notes", micAudioPath: nil, systemAudioPath: nil)
        _ = try store.prepareMeetingForResume(id: id)
        try store.appendLiveTranscriptCheckpoints(meetingID: id, entries: [
            LiveTranscriptCheckpointEntry(timestampLabel: "[00:00]", speaker: "You", startSeconds: 0, endSeconds: 1, text: "Checkpoint")
        ])
        try execute("CREATE TRIGGER reject_meeting_delete BEFORE UPDATE OF deleted_at ON meetings BEGIN SELECT RAISE(ABORT, 'test failure'); END", store: store)
        #expect(throws: (any Error).self) { try store.clearMeetings() }
        #expect(try count("meeting_resume_snapshots", store: store) == 1)
        #expect(try count("meeting_transcript_checkpoints", store: store) == 1)
        #expect(try store.meeting(id: id) != nil)
    }

    @Test("Cloud meeting tombstones remove owned audio and preserve files referenced by a live meeting")
    func cloudDeletionCleansAudio() throws {
        let store = try makeStore()
        let root = store.databasePath().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["mic.wav", "system.wav", "saved.m4a"].map { root.appendingPathComponent($0) }
        for path in paths { try Data("fixture".utf8).write(to: path) }
        let now = Date()
        let id = try store.insertMeeting(title: "Original", calendarEventID: nil, startTime: now, endTime: now,
            rawTranscript: "", formattedNotes: "", micAudioPath: paths[0].path, systemAudioPath: paths[1].path, savedRecordingPath: paths[2].path)
        let sharedID = try store.insertMeeting(title: "Shared", calendarEventID: nil, startTime: now, endTime: now,
            rawTranscript: "", formattedNotes: "", micAudioPath: nil, systemAudioPath: nil, savedRecordingPath: paths[2].path)
        let outbound = try #require(try store.textRecordsNeedingSync().first { $0.kind == .meeting && $0.title == "Original" })
        var tombstone = outbound
        tombstone.isDeleted = true
        tombstone.text = ""
        tombstone.updatedAt = outbound.updatedAt.addingTimeInterval(10)
        #expect(try store.upsertSyncedTextRecord(tombstone))
        #expect(try store.meeting(id: id) == nil)
        #expect(!FileManager.default.fileExists(atPath: paths[0].path))
        #expect(!FileManager.default.fileExists(atPath: paths[1].path))
        #expect(FileManager.default.fileExists(atPath: paths[2].path))
        #expect(try store.meeting(id: sharedID)?.savedRecordingPath == paths[2].path)
        #expect(try store.purgeSoftDeletedTextRecords(olderThan: 0, now: tombstone.updatedAt.addingTimeInterval(1)).meetings == 1)
    }

    @Test("Failed audio cleanup retains the tombstone path until cleanup can be retried")
    func failedAudioCleanupPreventsPurge() throws {
        let store = try makeStore()
        let root = store.databasePath().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("unremovable.m4a")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: false)
        let now = Date()
        _ = try store.insertMeeting(title: "Original", calendarEventID: nil, startTime: now, endTime: now,
            rawTranscript: "", formattedNotes: "", micAudioPath: nil, systemAudioPath: nil, savedRecordingPath: audio.path)
        var tombstone = try #require(try store.textRecordsNeedingSync().first { $0.kind == .meeting })
        tombstone.isDeleted = true
        tombstone.updatedAt = tombstone.updatedAt.addingTimeInterval(10)
        #expect(try store.upsertSyncedTextRecord(tombstone))
        #expect(try store.purgeSoftDeletedTextRecords(olderThan: 0, now: tombstone.updatedAt.addingTimeInterval(1)).meetings == 0)
        #expect(FileManager.default.fileExists(atPath: audio.path))
        try FileManager.default.removeItem(at: audio)
        try Data("fixture".utf8).write(to: audio)
        #expect(try store.purgeSoftDeletedTextRecords(olderThan: 0, now: tombstone.updatedAt.addingTimeInterval(1)).meetings == 1)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }
}
