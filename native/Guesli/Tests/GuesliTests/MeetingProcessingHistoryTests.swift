import Foundation
import Testing
import GuesliCore
@testable import GuesliApp
import SQLite3

@Suite("Meeting processing history", .serialized, .guesliHermeticSupport)
struct MeetingProcessingHistoryTests {
    private func fixture() throws -> (DictationStore, URL, Int64) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gm02-\(UUID().uuidString)")
        let store = DictationStore(databaseURL: root.appendingPathComponent("history.sqlite"))
        try store.migrateIfNeeded()
        let id = try store.insertMeeting(title: "Релиз", calendarEventID: nil, startTime: Date(timeIntervalSince1970: 1000),
            endTime: Date(timeIntervalSince1970: 1100), rawTranscript: "Old transcript", formattedNotes: "Old summary",
            micAudioPath: nil, systemAudioPath: nil)
        return (store, root, id)
    }

    private func summary(_ store: DictationStore, id: Int64, attempt: String, text: String = "New summary") throws {
        try store.saveMeetingProcessingSummary(meetingID: id, attemptID: attempt, notes: text,
            selectedTemplateID: "simple", selectedTemplateName: "Simple", selectedTemplateKind: .auto, selectedTemplatePrompt: "")
    }

    @Test func legacyMigrationAndNoOpDoNotInventHistoryOrStaleness() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.migrateIfNeeded()
        #expect(try store.meetingProcessingAttempts(meetingID: id).isEmpty)
        let before = try #require(try store.meeting(id: id))
        #expect(before.summaryInputRevision == nil)
        #expect(!before.summaryIsStale)
        try store.updateMeetingTitle(id: id, title: before.title)
        try store.updateMeetingManualNotes(id: id, manualNotes: before.manualNotes)
        #expect(try store.meeting(id: id)?.contentRevision == before.contentRevision)
        try store.updateMeetingManualNotes(id: id, manualNotes: "Decision")
        let edited = try #require(try store.meeting(id: id))
        #expect(edited.contentRevision == before.contentRevision + 1)
        #expect(edited.summaryIsStale)
        #expect(edited.formattedNotes == "Old summary")
    }

    @Test func asrSurvivesSummaryFailureAndSnapshotDoesNotChange() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.updateMeetingManualNotes(id: id, manualNotes: "Manual note")
        let config = MeetingProcessingConfiguration(asrBackend: "local", asrModel: "model-at-start",
            summaryBackend: "chatgpt", summaryModel: "summary-at-start", audioSources: ["mixed"], completeness: .incomplete)
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .retranscription, configuration: config)
        try store.saveMeetingProcessingTranscript(meetingID: id, attemptID: attempt, transcript: "New ASR", originalTranscript: nil)
        try store.finishMeetingProcessing(attemptID: attempt, outcome: .failed, safeError: "Summary generation failed.")
        let record = try #require(try store.meeting(id: id))
        #expect(record.rawTranscript == "New ASR")
        #expect(record.manualNotes == "Manual note")
        #expect(record.formattedNotes == "Old summary")
        #expect(record.summaryIsStale)
        #expect(record.transcriptAttemptID == attempt)
        let saved = try #require(try store.meetingProcessingAttempts(meetingID: id).first)
        #expect(saved.configuration == config)
        #expect(saved.stage == "summary")
        #expect(saved.outcome == .failed)
    }

    @Test func failedPersistenceRollsBackTextAndAttemptLink() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .retranscription, configuration: .init())
        var db: OpaquePointer?
        #expect(sqlite3_open(store.resolvedDatabaseURL.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_attempt_update BEFORE UPDATE ON meeting_processing_attempts BEGIN SELECT RAISE(ABORT, 'fixture failure'); END", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) {
            try store.saveMeetingProcessingTranscript(meetingID: id, attemptID: attempt, transcript: "Must roll back", originalTranscript: nil)
        }
        let record = try #require(try store.meeting(id: id))
        #expect(record.rawTranscript == "Old transcript")
        #expect(record.transcriptAttemptID == nil)
        #expect(record.contentRevision == 0)
    }

    @Test func staleSummaryAndManualSummaryEditsRejectLateWrites() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init())
        try store.updateMeetingTranscript(id: id, rawTranscript: "Edited during request")
        #expect(throws: MeetingProcessingError.self) { try summary(store, id: id, attempt: first) }
        #expect(try store.meeting(id: id)?.formattedNotes == "Old summary")
        try store.finishMeetingProcessing(attemptID: first, outcome: .failed)
        let next = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init())
        try store.updateMeetingNotes(id: id, formattedNotes: "Human edited summary")
        #expect(throws: MeetingProcessingError.self) { try summary(store, id: id, attempt: next) }
        #expect(try store.meeting(id: id)?.formattedNotes == "Human edited summary")
    }

    @Test func summaryOnlyWorksWithoutAudioAndClearsOnlyItsBasis() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.updateMeetingTranscript(id: id, rawTranscript: "Corrected names")
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init(summaryModel: "captured"))
        try summary(store, id: id, attempt: attempt)
        let record = try #require(try store.meeting(id: id))
        #expect(record.rawTranscript == "Corrected names")
        #expect(record.summaryInputRevision == record.contentRevision)
        #expect(!record.summaryIsStale)
        #expect(record.summaryAttemptID == attempt)
        #expect(try store.meetingProcessingAttempts(meetingID: id).first?.outcome == .succeeded)
        try store.updateMeetingManualNotes(id: id, manualNotes: "New fact")
        #expect(try store.meeting(id: id)?.summaryIsStale == true)
    }

    @Test func concurrentAttemptsCancellationRecoveryAndDeletion() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init())
        #expect(throws: MeetingProcessingError.self) {
            try store.beginMeetingProcessing(meetingID: id, operation: .retranscription, configuration: .init())
        }
        try store.finishMeetingProcessing(attemptID: attempt, outcome: .cancelled)
        #expect(throws: MeetingProcessingError.self) { try summary(store, id: id, attempt: attempt) }
        _ = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init())
        try store.interruptUnfinishedMeetingProcessing()
        #expect(try store.meetingProcessingAttempts(meetingID: id).first?.outcome == .interrupted)
        #expect(try store.meeting(id: id)?.formattedNotes == "Old summary")
        try store.deleteMeeting(id: id)
        #expect(try store.meetingProcessingAttempts(meetingID: id).isEmpty)
        #expect(try store.meeting(id: id) == nil)
    }

    @Test func emptyAndRawFallbackDoNotReplaceSavedSummary() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .summary, configuration: .init())
        #expect(throws: MeetingProcessingError.self) { try summary(store, id: id, attempt: attempt, text: "  ") }
        #expect(throws: MeetingProcessingError.self) { try summary(store, id: id, attempt: attempt, text: "## Raw Transcript\n\nFallback") }
        #expect(try store.meeting(id: id)?.formattedNotes == "Old summary")
    }

    @Test func speakerCorrectionDismissalAndStaleBannerCAS() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try #require(try store.meeting(id: id))
        try store.updateMeetingSpeakerAttribution(id: id, expectedTranscriptRevision: before.transcriptRevision,
            rawTranscript: "Corrected speaker", speakerAttributionJSON: MeetingSpeakerAttribution.legacy(transcript: "Corrected speaker").json!)
        let corrected = try #require(try store.meeting(id: id))
        #expect(corrected.summaryIsStale)
        try store.dismissMeetingSummaryStaleness(id: id, expectedContentRevision: corrected.contentRevision)
        #expect(try store.meeting(id: id)?.summaryStalenessDismissedRevision == corrected.contentRevision)
        #expect(try store.meeting(id: id)?.summaryIsStale == true)
        #expect(throws: MeetingProcessingError.self) {
            try store.updateMeetingSpeakerAttribution(id: id, expectedTranscriptRevision: before.transcriptRevision,
                rawTranscript: "Wrong old screen", speakerAttributionJSON: MeetingSpeakerAttribution.legacy(transcript: "Wrong old screen").json!)
        }
        try store.updateMeetingManualNotes(id: id, manualNotes: "New input")
        #expect(try store.meeting(id: id)?.summaryStalenessDismissedRevision == nil)
    }

    @Test func importInitialAttemptAndProgressiveTextAreDurable() throws {
        let (store, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let imported = try store.beginImportedMeetingProcessing(title: "Imported", startTime: Date(), duration: 30,
            savedRecordingPath: "/fixture/retained.wav", configuration: .init(audioSources: ["imported"]))
        try store.saveMeetingProcessingTranscript(meetingID: imported.meetingID, attemptID: imported.attemptID, transcript: "ASR", originalTranscript: nil)
        try store.saveMeetingProcessingTranscript(meetingID: imported.meetingID, attemptID: imported.attemptID, transcript: "Cleaned", originalTranscript: "ASR")
        #expect(try store.meeting(id: imported.meetingID)?.rawTranscript == "Cleaned")
        #expect(try store.meeting(id: imported.meetingID)?.savedRecordingPath == "/fixture/retained.wav")
        try summary(store, id: imported.meetingID, attempt: imported.attemptID)
        #expect(try store.meetingProcessingAttempts(meetingID: imported.meetingID).first?.operation == .initial)
    }
    @MainActor
    @Test func stopCancelsTrackedWorkAndRejectsLatePersistence() async throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let controller = GuesliController(
            runtime: RuntimePaths(repoRoot: root, menuIcon: nil, appIcon: nil, bundlePath: nil),
            configStore: ConfigStore(supportURL: root.appendingPathComponent("support")), dictationStore: store)
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .initial, configuration: .init())
        let task = Task<Void, Never> { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        controller.trackMeetingProcessingTask(meetingID: id, attemptID: attempt, task: task)
        controller.cancelMeetingProcessing(id: id)
        await task.value
        #expect(task.isCancelled)
        #expect(try store.meetingProcessingAttempts(meetingID: id).first?.outcome == .cancelled)
        #expect(throws: MeetingProcessingError.self) {
            try store.saveMeetingProcessingTranscript(meetingID: id, attemptID: attempt,
                transcript: "Late transcript", originalTranscript: nil)
        }
        #expect(try store.meeting(id: id)?.rawTranscript == "Old transcript")
        try store.appendLiveTranscriptCheckpoints(meetingID: id, entries: [
            LiveTranscriptCheckpointEntry(timestampLabel: "00:00:01", speaker: "You", startSeconds: 1, endSeconds: 2, text: "Unaccepted new draft")
        ])
        controller.resolveLiveMeetingAfterStopFailure(id: id, recoverTranscript: false)
        #expect(try store.meeting(id: id)?.rawTranscript == "Old transcript")
        #expect(try store.meeting(id: id)?.formattedNotes == "Old summary")
        #expect(try store.meeting(id: id)?.status == .completed)
    }

    @Test func initialParallelSummaryKeepsItsDifferentBasisStale() throws {
        let (store, root, id) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try store.beginMeetingProcessing(meetingID: id, operation: .initial, configuration: .init())
        try store.completeLiveMeeting(id: id, title: "Релиз", calendarEventID: nil,
            startTime: Date(timeIntervalSince1970: 1000), endTime: Date(timeIntervalSince1970: 1100),
            rawTranscript: "Cleaned transcript", rawOriginalTranscript: "Raw transcript",
            formattedNotes: "Summary of raw text", micAudioPath: nil, systemAudioPath: nil,
            processingAttemptID: attempt, summaryInputMatchesTranscript: false)
        let record = try #require(try store.meeting(id: id))
        #expect(record.rawTranscript == "Cleaned transcript")
        #expect(record.formattedNotes == "Summary of raw text")
        #expect(record.summaryIsStale)
        #expect(record.summaryInputRevision == nil)
        #expect(record.summaryAttemptID == attempt)
    }

}
