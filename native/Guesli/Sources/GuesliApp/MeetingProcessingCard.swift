import SwiftUI

extension MeetingProcessingStage {
    var cardLabel: String {
        switch self {
        case .transcribingAudio: return "Финальное распознавание…"
        case .cleaningAudio: return "Очищаем звук…"
        case .generatingTitle: return "Придумываем название…"
        case .summarizingNotes: return "Готовим итог…"
        }
    }
}

// Sole observer of the live transcript and processing stage while a meeting is
// processing, so MeetingDetailView.body does not re-render on every chunk.
struct MeetingProcessingDraftSection: View {
    let appState: AppState
    let meetingID: Int64
    let transcriptPrefix: String

    var body: some View {
        let stage = appState.meetingProcessingStages[meetingID] ?? .transcribingAudio
        let ownsLiveTranscript = appState.liveMeetingTranscriptOwnerID == meetingID
        let prior = transcriptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let live = ownsLiveTranscript
            ? appState.liveMeetingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
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

            Text("Черновик живой расшифровки — заменится финальной после обработки")
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textTertiary)

            LiveTranscriptView(
                transcript: transcript,
                placeholder: "Живой расшифровки нет — ждём финальную",
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
                Text("Не удалось обработать встречу")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(canRetry
                    ? "Ручные заметки сохранены. Запись можно распознать заново."
                    : "Ручные заметки сохранены.")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textSecondary)
            }
            Spacer(minLength: GuesliTheme.spacing8)
            if canRetry {
                Button("Повторить", action: onRetry)
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
