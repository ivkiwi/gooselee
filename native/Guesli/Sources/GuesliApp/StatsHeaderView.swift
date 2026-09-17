import SwiftUI
import GuesliCore

struct StatsHeaderView: View {
    let dictationStats: DictationStats
    let meetingStats: MeetingStats

    var body: some View {
        HStack(spacing: GuesliTheme.spacing16) {
            StatCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(dictationStats.currentStreakDays)",
                label: "day streak"
            )
            StatCard(
                icon: "character.cursor.ibeam",
                iconColor: GuesliTheme.accent,
                value: formatWordCount(dictationStats.totalWords),
                label: "words dictated"
            )
            StatCard(
                icon: "gauge.with.dots.needle.33percent",
                iconColor: GuesliTheme.success,
                value: String(format: "%.0f", dictationStats.averageWPM),
                label: "avg WPM"
            )
            StatCard(
                icon: "person.2.fill",
                iconColor: GuesliTheme.accent,
                value: "\(meetingStats.totalMeetings)",
                label: "meetings"
            )
        }
        .padding(.horizontal, GuesliTheme.spacing24)
        .padding(.vertical, GuesliTheme.spacing20)
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: GuesliTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
            Text(value)
                .font(GuesliTheme.title2())
                .foregroundStyle(GuesliTheme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
