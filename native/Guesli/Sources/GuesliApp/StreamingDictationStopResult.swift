import Foundation

struct StreamingDictationStopResult: Sendable {
    let text: String
    var recordingURL: URL? = nil
    var isComplete = true
}

enum StreamingDictationRecovery {
    static func recover(_ result: StreamingDictationStopResult, startedAt: Date, supportDirectory: URL) -> String {
        guard let wavURL = result.recordingURL else {
            return String(localized: "Streaming transcription did not finish. Some words may be missing; no recording was available for recovery.")
        }
        do {
            let recoveryURL = try retainRecording(wavURL, startedAt: startedAt, supportDirectory: supportDirectory)
            return String(localized: "Streaming transcription did not finish. Import the saved recording to transcribe the rest: \(recoveryURL.path)")
        } catch {
            return String(localized: "Streaming transcription did not finish. Could not move the recording to recovery storage. Copy it before restarting: \(wavURL.path)")
        }
    }

    static func retainRecording(_ url: URL, startedAt: Date, supportDirectory: URL) throws -> URL {
        try MeetingRecordingStorage.persistTemporaryRecording(
            from: url,
            meetingTitle: "Dictation",
            startedAt: startedAt,
            destinationDirectory: supportDirectory.appendingPathComponent("dictation-recovery", isDirectory: true),
            fileFormat: .wav
        )
    }
}
