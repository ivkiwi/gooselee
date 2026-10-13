import SwiftUI

struct TranscriptTimestampButton: View {
    let timestamp: String
    let unavailableReason: String?
    let onSeek: () -> Void

    var body: some View {
        Button(action: onSeek) {
            Text(verbatim: timestamp)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(unavailableReason == nil ? GuesliTheme.accent : GuesliTheme.textTertiary)
                .underline(unavailableReason == nil)
                .padding(.horizontal, 3)
                .frame(minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .disabled(unavailableReason != nil)
        .accessibilityLabel(Text("Play recording from \(timestamp)"))
        .accessibilityHint(Text(verbatim: helpText))
        .help(helpText)
    }

    private var helpText: String {
        unavailableReason ?? String(localized: "Seek and play recording")
    }
}
