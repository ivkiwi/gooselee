import AVFoundation
import Foundation
import GuesliCore

@MainActor
enum DictationTextRecovery {
    static func save(
        _ text: String,
        insert: @MainActor (String) throws -> Void,
        copyToClipboard: @MainActor (String) -> Void
    ) -> Bool {
        do {
            try insert(text)
            return true
        } catch {
            copyToClipboard(text)
            return false
        }
    }

    static var failureMessage: String {
        String(localized: "Could not save dictation. Text is in the clipboard — paste it manually (⌘V).")
    }
}

enum DictationRecordingRecovery {
    /// Keep finalized WAVs outside the temporary sweep until processing succeeds.
    static func retainForRetry(_ sourceURL: URL, supportDirectory: URL) -> URL {
        GuesliPaths.preconditionSafeForTestWrite(sourceURL)
        // The temporary sibling is also excluded from the normal launch sweep.
        let directories = [
            supportDirectory.appendingPathComponent("failed-dictations", isDirectory: true),
            sourceURL.deletingLastPathComponent().appendingPathExtension("recovery"),
        ]
        for directory in directories {
            let destination = directory.appendingPathComponent("dictation-\(UUID().uuidString).wav")
            GuesliPaths.preconditionSafeForTestWrite(destination)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: sourceURL, to: destination)
                return destination
            } catch {
                continue
            }
        }
        return sourceURL
    }

    static func containsAudio(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return true }
        return file.length > 0
    }

    static func finishProcessing(_ url: URL, succeeded: Bool) {
        guard succeeded else { return }
        GuesliPaths.preconditionSafeForTestWrite(url)
        try? FileManager.default.removeItem(at: url)
    }

    static func failureMessage(recordingURL: URL) -> String {
        if AppTemporaryDirectories.launchSweepDirectoryNames.contains(recordingURL.deletingLastPathComponent().lastPathComponent) {
            return String(localized: "Recording could not be archived. Copy \(recordingURL.path) to a safe folder before quitting.")
        }
        return String(localized: "The recording was kept at \(recordingURL.path). Import this WAV to retry.")
    }
}
