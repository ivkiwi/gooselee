import SwiftUI

struct MeetingPreparationBanner: View {
    let status: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: GuesliTheme.spacing12) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
                .accessibilityLabel("Preparing transcription")

            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing transcription")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(status ?? "Meeting transcription will start shortly.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: GuesliTheme.spacing12)

            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark.circle")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Cancel meeting preparation")
        }
        .padding(GuesliTheme.spacing12)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerLarge)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
