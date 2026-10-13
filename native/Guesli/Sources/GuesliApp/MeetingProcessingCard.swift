import SwiftUI

extension MeetingProcessingStage {
    var cardLabel: String {
        switch self {
        case .transcribingAudio: return String(localized: "Final transcription…")
        case .cleaningAudio: return String(localized: "Cleaning audio…")
        case .generatingTitle: return String(localized: "Naming meeting…")
        case .summarizingNotes: return String(localized: "Summarizing…")
        }
    }
}

// Sole observer of the live transcript and processing stage while a meeting is
// processing, so MeetingDetailView.body does not re-render on every chunk.
struct MeetingProcessingDraftSection: View {
    let appState: AppState
    let controller: GuesliController
    let meetingID: Int64
    let transcriptPrefix: String
    @State private var checkpointDraft: String?

    var body: some View {
        let stage = appState.meetingProcessingStages[meetingID] ?? .transcribingAudio
        let ownsLiveTranscript = appState.liveMeetingTranscriptOwnerID == meetingID
        let prior = transcriptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        // Another recording took over the live buffer; fall back to this meeting's saved checkpoints.
        let live = (ownsLiveTranscript ? appState.liveMeetingTranscript : checkpointDraft ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = [prior, live].filter { !$0.isEmpty }.joined(separator: "\n\n— Resumed —\n\n")
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(spacing: GuesliTheme.spacing8) {
                ProgressView()
                    .controlSize(.small)
                Text(stage.cardLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textPrimary)
            }
            .accessibilityElement(children: .combine)

            Text("Live draft — replaced by the final transcript when processing ends")
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textTertiary)

            LiveTranscriptView(
                transcript: transcript,
                placeholder: String(localized: "No live transcript — waiting for the final one"),
                partialYou: ownsLiveTranscript ? appState.liveMeetingPartialYou : "",
                partialOthers: ownsLiveTranscript ? appState.liveMeetingPartialOthers : ""
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        // Checkpoints stop growing once the owner switches, so one read per meeting is enough.
        .task(id: ownsLiveTranscript ? nil : meetingID) {
            checkpointDraft = ownsLiveTranscript ? nil : controller.liveTranscriptCheckpointDraft(meetingID: meetingID)
        }
    }
}

struct MeetingProcessingFailedBanner: View {
    let canRetry: Bool
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: GuesliTheme.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GuesliTheme.transcribing)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't process meeting")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(canRetry
                    ? "Your notes are saved. You can transcribe the recording again."
                    : "Your notes are saved.")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textSecondary)
            }
            Spacer(minLength: GuesliTheme.spacing8)
            if canRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetrying)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, GuesliTheme.spacing8)
        .background(GuesliTheme.transcribing.opacity(0.10))
    }
}
