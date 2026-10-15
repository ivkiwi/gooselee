import Foundation

protocol MeetingTranscriptCleaning: Sendable {
    func cleanupMeetingTranscript(_ transcript: String, config: AppConfig) async throws -> String
}

struct ChatGPTMeetingTranscriptCleaner: MeetingTranscriptCleaning {
    func cleanupMeetingTranscript(_ transcript: String, config: AppConfig) async throws -> String {
        try await MeetingSummaryClient.cleanupMeetingTranscriptWithChatGPT(
            transcript: transcript,
            config: config
        )
    }
}

struct MeetingTranscriptCleanupResult: Equatable, Sendable {
    let transcript: String
    let originalTranscript: String?
    let cleanupAttempted: Bool

    init(transcript: String, originalTranscript: String?, cleanupAttempted: Bool = false) {
        self.transcript = transcript
        self.originalTranscript = originalTranscript
        self.cleanupAttempted = cleanupAttempted
    }
}

enum MeetingTranscriptCleanupPipeline {
    static func cleanIfNeeded(
        transcript: String,
        config: AppConfig,
        isChatGPTAuthenticated: Bool,
        cleaner: MeetingTranscriptCleaning,
        onCleanupAttempted: (@Sendable () -> Void)? = nil
    ) async -> MeetingTranscriptCleanupResult {
        let rawTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTranscript.isEmpty else {
            return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil)
        }
        guard config.enableMeetingTranscriptCleanup else {
            return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil)
        }
        guard config.resolvedMeetingTranscriptCleanupProvider == .chatGPT else {
            DiagnosticsLog.write("[meeting-cleanup] unsupported provider \(config.meetingTranscriptCleanupProvider); keeping raw transcript")
            return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil)
        }
        guard isChatGPTAuthenticated else {
            DiagnosticsLog.write("[meeting-cleanup] ChatGPT not authenticated; keeping raw transcript")
            return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil)
        }

        onCleanupAttempted?()
        do {
            let cleaned = try await cleaner.cleanupMeetingTranscript(rawTranscript, config: config)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                DiagnosticsLog.write("[meeting-cleanup] empty cleanup response; keeping raw transcript")
                return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil, cleanupAttempted: true)
            }
            guard cleaned != rawTranscript else {
                return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil, cleanupAttempted: true)
            }
            DiagnosticsLog.write("[meeting-cleanup] cleaned transcript chars raw=\(rawTranscript.count) cleaned=\(cleaned.count)")
            return MeetingTranscriptCleanupResult(transcript: cleaned, originalTranscript: transcript, cleanupAttempted: true)
        } catch {
            DiagnosticsLog.write("[meeting-cleanup] cleanup failed, keeping raw transcript: \(error.localizedDescription)")
            return MeetingTranscriptCleanupResult(transcript: transcript, originalTranscript: nil, cleanupAttempted: true)
        }
    }
}
