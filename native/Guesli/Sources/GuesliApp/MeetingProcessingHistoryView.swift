import SwiftUI
import GuesliCore

struct MeetingProcessingHistoryView: View {
    let meeting: MeetingRecord
    let attempts: [MeetingProcessingAttempt]
    var onCancel: (() -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
                if attempts.isEmpty {
                    Text("No processing history was recorded for this meeting.")
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
                ForEach(attempts) { attempt in
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(operationLabel(attempt.operation)).fontWeight(.medium)
                            Spacer()
                            Text(Date(timeIntervalSince1970: attempt.startedAt), style: .date)
                            Text(Date(timeIntervalSince1970: attempt.startedAt), style: .time)
                        }
                        Text(outcomeLabel(attempt.outcome))
                            .foregroundStyle(attempt.outcome == .failed || attempt.outcome == .interrupted
                                ? GuesliTheme.transcribing : GuesliTheme.textSecondary)
                        Text(stageLabel(attempt.stage))
                            .foregroundStyle(GuesliTheme.textSecondary)
                        Text(modelDescription(attempt.configuration))
                            .textSelection(.enabled)
                        if !attempt.configuration.audioSources.isEmpty {
                            Text(attempt.configuration.audioSources.map(sourceLabel).joined(separator: ", "))
                        }
                        if let model = attempt.configuration.cleanupModel {
                            Text(String(localized: "Transcript cleanup model") + ": " + model)
                        }
                        if attempt.configuration.diarizationEnabled { Text("Speaker diarization completed") }
                        Text(attempt.configuration.completeness == .incomplete
                            ? String(localized: "Source recording is incomplete") : String(localized: "Source completeness unknown"))
                            .foregroundStyle(GuesliTheme.textSecondary)
                        ForEach(attempt.configuration.warnings, id: \.self) { warning in
                            Text(NSLocalizedString(warning, comment: "Processing source warning"))
                                .foregroundStyle(GuesliTheme.transcribing)
                        }
                        if let error = attempt.safeError {
                            Text(NSLocalizedString(error, comment: "Safe processing error"))
                                .foregroundStyle(GuesliTheme.transcribing)
                        }
                        if attempt.outcome == .running, let onCancel {
                            Button("Stop processing", action: onCancel).controlSize(.small)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    if attempt.id != attempts.last?.id { Divider() }
                }
                if !hasAudio {
                    Text("Transcription retry is unavailable because the recording is missing. You can still update the summary from saved text.")
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
            }
            .font(GuesliTheme.caption())
            .padding(.top, GuesliTheme.spacing8)
        } label: {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                Text("Processing").font(GuesliTheme.headline())
                Text(String(localized: "Transcript") + ": " + origin(meeting.transcriptAttemptID, summary: false))
                Text(String(localized: "Summary") + ": " + origin(meeting.summaryAttemptID, summary: true))
            }
            .font(GuesliTheme.caption())
            .foregroundStyle(GuesliTheme.textSecondary)
        }
    }

    private var hasAudio: Bool {
        [meeting.savedRecordingPath, meeting.micAudioPath, meeting.systemAudioPath]
            .compactMap { $0 }.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func origin(_ id: String?, summary: Bool) -> String {
        guard let id, let attempt = attempts.first(where: { $0.id == id }) else { return String(localized: "Origin unknown") }
        let config = attempt.configuration
        return [summary ? config.summaryBackend : config.asrBackend, summary ? config.summaryModel : config.asrModel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func modelDescription(_ config: MeetingProcessingConfiguration) -> String {
        [config.asrBackend, config.asrModel, config.summaryBackend, config.summaryModel]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func operationLabel(_ operation: MeetingProcessingOperation) -> String {
        switch operation {
        case .initial: return String(localized: "Initial processing")
        case .retranscription: return String(localized: "Transcription retry")
        case .summary: return String(localized: "Summary retry")
        }
    }

    private func outcomeLabel(_ outcome: MeetingProcessingOutcome) -> String {
        switch outcome {
        case .running: return String(localized: "Processing in progress")
        case .succeeded: return String(localized: "Saved successfully")
        case .failed: return String(localized: "Processing failed")
        case .cancelled: return String(localized: "Processing cancelled")
        case .interrupted: return String(localized: "Processing interrupted")
        }
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "asr", "transcribingAudio": return String(localized: "Transcribing audio")
        case "summary", "summarizingNotes": return String(localized: "Generating summary")
        case "cleaningAudio": return String(localized: "Cleaning audio")
        case "generatingTitle": return String(localized: "Naming meeting")
        case "saved": return String(localized: "Result saved")
        default: return String(localized: "Processing")
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "microphone": return String(localized: "Microphone track")
        case "system": return String(localized: "System audio track")
        case "imported": return String(localized: "Imported audio file")
        case "mixed": return String(localized: "Mixed recording")
        default: return String(localized: "Source unknown")
        }
    }
}
