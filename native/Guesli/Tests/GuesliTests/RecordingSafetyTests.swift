import Foundation
import GuesliCore
import Testing
@testable import GuesliApp

@Suite("Recording safety", .guesliHermeticSupport)
struct RecordingSafetyTests {
    @Test("WAV finalization preserves complete samples from a partial write")
    func finalizesPartialSampleWrite() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try (WavWriter.header(dataSize: 0) + Data([0x34, 0x12, 0xAB])).write(to: url)
        let handle = try FileHandle(forUpdating: url)
        #expect(try RecordingWAVFileIO.finalize(handle) == 2)
        let data = try Data(contentsOf: url)
        #expect(data.count == 46)
        #expect(data.subdata(in: 40..<44) == Data([2, 0, 0, 0]))
        #expect(data.suffix(2) == Data([0x34, 0x12]))
    }

    @Test("write failures throw without destroying existing audio")
    func writeFailurePreservesAudio() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = WavWriter.header(dataSize: 2) + Data([1, 0])
        try original.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        do {
            try RecordingWAVFileIO.append(Data([2, 0]), to: handle, bytesWritten: 2)
            Issue.record("Expected a write error from a read-only handle")
        } catch {
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test("failed header repair keeps the available complete sample count")
    func failedHeaderRepairKeepsSampleCount() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = WavWriter.header(dataSize: 0) + Data([1, 0, 2])
        try original.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        #expect(RecordingWAVFileIO.finalizePreservingFile(handle) == 2)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("oversized WAV data is rejected before file mutation")
    func rejectsOversizedWAV() throws {
        do {
            try RecordingWAVFileIO.validateDataSize(Int(UInt32.max) + 1)
            Issue.record("Expected the WAV size limit")
        } catch RecordingWAVFileIO.Failure.sizeLimit {}
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let header = WavWriter.header(dataSize: 0)
        try header.write(to: url)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        do {
            try RecordingWAVFileIO.append(Data([1, 0]), to: handle, bytesWritten: RecordingWAVFileIO.maximumDataSize - 1)
            Issue.record("Expected the next write to exceed the WAV limit")
        } catch RecordingWAVFileIO.Failure.sizeLimit {}
        #expect(try Data(contentsOf: url) == header)
    }

#if DEBUG
    @Test("retained writer stops after one write failure and keeps its finalized prefix")
    func retainedWriterStopsAfterWriteFailure() throws {
        let writer = try MeetingRecordingWriter()
        defer { writer.cancel() }
        writer.appendMic([1, 2])
        writer.appendSystem([3, 4])
        try writer.failWritesForTesting()
        var failures = 0
        writer.onRecordingFailed = { _ in failures += 1 }
        writer.appendMic([5, 6])
        writer.appendSystem([7, 8])
        writer.appendMic([9, 10])
        writer.appendSystem([11, 12])
        let url = try #require(writer.stop())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(failures == 1)
        #expect(try Data(contentsOf: url).suffix(4) == Data([2, 0, 3, 0]))
    }
#endif

    @MainActor
    @Test("stop failure recovers checkpoint transcript and keeps the failed meeting")
    func stopFailureKeepsCheckpoints() throws {
        let (controller, store, root) = try makeController()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try store.createLiveMeeting(title: "Stop failure", calendarEventID: nil, startTime: Date())
        try store.appendLiveTranscriptCheckpoints(meetingID: id, entries: [
            LiveTranscriptCheckpointEntry(timestampLabel: "10:00:02", speaker: "Others", startSeconds: 2, endSeconds: 3, text: "Checkpoint content")
        ])
        controller.resolveLiveMeetingAfterStopFailure(id: id)
        let meeting = try #require(try store.meeting(id: id))
        #expect(meeting.status == .failed)
        #expect(meeting.rawTranscript.contains("Checkpoint content"))
    }

    @MainActor
    @Test("retained audio is linked before processing and survives a stop failure")
    func earlyRetainedAudioSurvivesFailure() async throws {
        let (controller, store, root) = try makeController()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date()
        let id = try store.createLiveMeeting(title: "Retained audio", calendarEventID: nil, startTime: start)
        let writer = try MeetingRecordingWriter(meetingID: id)
        defer { writer.cancel() }
        writer.appendMic([1, 2])
        writer.appendSystem([3, 4])
        let tempURL = try #require(writer.stop())
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let staged = try #require(try await controller.persistRetainedMeetingRecording(
            RetainedMeetingRecordingFinalizeRequest(tempURL: tempURL, meetingTitle: "Retained audio", startedAt: start),
            meetingID: id
        ))
        #expect(try store.meeting(id: id)?.savedRecordingPath == staged.path)
        controller.resolveLiveMeetingAfterStopFailure(id: id)
        #expect(try store.meeting(id: id)?.status == .failed)
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @MainActor
    @Test("discard waits for successful database persistence")
    func discardWaitsForPersistence() async throws {
        let (controller, store, root) = try makeController()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("recovery"))
        }
        try (WavWriter.header(dataSize: 2) + Data([1, 0])).write(to: url)
        let result = MeetingSessionResult(
            title: "Deferred discard", originalTitle: "Meeting", calendarEventID: nil,
            startTime: Date(), endTime: Date(), durationSeconds: 1,
            rawTranscript: "Saved transcript", formattedNotes: "",
            retainedRecordingURL: url, retainedRecordingError: nil, systemRecordingURL: nil,
            templateSnapshot: MeetingTemplates.auto.snapshot
        )
        let prepared = await controller.prepareMeetingRecordingSave(for: result)
        #expect(FileManager.default.fileExists(atPath: url.path))
        do {
            _ = try controller.persistCompletedMeetingResult(result, existingMeetingID: -1, preparedRecordingSave: prepared)
            Issue.record("Expected persistence to fail for a missing meeting")
        } catch {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        let persisted = try controller.persistCompletedMeetingResult(result, preparedRecordingSave: prepared)
        #expect(try store.meeting(id: persisted.meetingID)?.savedRecordingPath == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("meeting log calls never interpolate transcript text")
    func logsDoNotContainTranscriptText() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GuesliApp/MeetingSession.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let textLogLines = source.split(separator: "\n").filter {
            ($0.contains("fputs(") || $0.contains("DiagnosticsLog.write(")) && $0.contains("result.text")
        }
        #expect(textLogLines.allSatisfy {
            !String($0).replacingOccurrences(of: "result.text.count", with: "").contains("result.text")
        })
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording-safety-\(UUID().uuidString).wav")
    }

    @MainActor
    private func makeController() throws -> (GuesliController, DictationStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recording-safety-\(UUID().uuidString)")
        let store = DictationStore(databaseURL: root.appendingPathComponent("history.db"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try store.migrateIfNeeded()
        let controller = GuesliController(
            runtime: RuntimePaths(repoRoot: root, menuIcon: nil, appIcon: nil, bundlePath: nil),
            configStore: ConfigStore(supportURL: root.appendingPathComponent("support")),
            dictationStore: store
        )
        return (controller, store, root)
    }
}
