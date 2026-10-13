import Foundation
import Testing
@testable import GuesliApp

@Suite("Dictation recovery", .guesliHermeticSupport)
@MainActor
struct DictationRecoveryTests {
    @Test("storage failure preserves the complete text in the clipboard", arguments: ["Voice note", "Typed dictation"])
    func failedSaveCopiesText(text: String) {
        var copied: String?
        let saved = DictationTextRecovery.save(text, insert: { _ in
            throw NSError(domain: "DictationRecoveryTests", code: 1)
        }, copyToClipboard: { copied = $0 })
        #expect(!saved)
        #expect(copied == text)
    }

    @Test("successful storage leaves the clipboard alone")
    func successfulSaveDoesNotCopy() {
        var inserted: String?
        var copied = false
        let saved = DictationTextRecovery.save("Saved note", insert: { inserted = $0 }, copyToClipboard: { _ in copied = true })
        #expect(saved)
        #expect(inserted == "Saved note")
        #expect(!copied)
    }

    @Test("failed ASR keeps the WAV outside the launch sweep; success removes it")
    func recordingSurvivesFailureAndSweep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-recovery-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = AppTemporaryDirectories.url(named: AppTemporaryDirectories.nativeDictation, temporaryDirectory: root)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("recording.wav")
        try WavWriter.writeWAV(samples: [0.1, -0.1], to: source)
        let originalData = try Data(contentsOf: source)

        let kept = DictationRecordingRecovery.retainForRetry(source, supportDirectory: root)
        #expect(kept.deletingLastPathComponent().lastPathComponent == "failed-dictations")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        DictationRecordingRecovery.finishProcessing(kept, succeeded: false)
        _ = AppTemporaryDirectories.sweepAtLaunch(temporaryDirectory: root, now: Date().addingTimeInterval(7_200), logger: nil)
        #expect(try Data(contentsOf: kept) == originalData)

        DictationRecordingRecovery.finishProcessing(kept, succeeded: true)
        #expect(!FileManager.default.fileExists(atPath: kept.path))
    }

    @Test("an archive failure preserves the original WAV")
    func archiveFailureKeepsOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-recovery-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("recording.wav")
        try WavWriter.writeWAV(samples: [0.25], to: source)
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        try Data().write(to: sourceDirectory.appendingPathExtension("recovery"))

        let kept = DictationRecordingRecovery.retainForRetry(source, supportDirectory: blocked)
        #expect(kept == source)
        DictationRecordingRecovery.finishProcessing(kept, succeeded: false)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(DictationRecordingRecovery.containsAudio(kept))
    }

    @Test("unavailable support storage falls back outside the temporary sweep")
    func archiveFailureUsesRecoverySibling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-recovery-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = AppTemporaryDirectories.url(named: AppTemporaryDirectories.nativeDictation, temporaryDirectory: root)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("recording.wav")
        try WavWriter.writeWAV(samples: [0.1], to: source)
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)

        let kept = DictationRecordingRecovery.retainForRetry(source, supportDirectory: blocked)
        #expect(kept.deletingLastPathComponent() == sourceDirectory.appendingPathExtension("recovery"))
        _ = AppTemporaryDirectories.sweepAtLaunch(temporaryDirectory: root, now: Date().addingTimeInterval(7_200), logger: nil)
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    @Test("unreadable audio is kept for manual recovery")
    func unreadableAudioIsNotDiscarded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-unreadable-test-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("unfinalized recording".utf8).write(to: url)
        #expect(DictationRecordingRecovery.containsAudio(url))
    }

    @Test("transcript log metadata contains sizes, never transcript content")
    func logsContainOnlyMetadata() throws {
        let text = "Private transcript: example phrase"
        let metadata = DictationLogMetadata(text: text)
        let data = try JSONEncoder().encode(metadata)
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Int]
        #expect(fields == ["characterCount": text.count])
        #expect(metadata.summary == "chars=\(text.count)")
        #expect(!metadata.summary.contains(text))
        #expect(!String(decoding: data, as: UTF8.self).contains(text))
    }
}
