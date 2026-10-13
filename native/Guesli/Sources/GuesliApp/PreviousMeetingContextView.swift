import SwiftUI
import GuesliCore

struct PreviousMeetingContextView: View {
    let meeting: MeetingRecord
    let onOpen: () -> Void

    var body: some View {
        let sections = PreviousMeetingNotes.extract(from: meeting.formattedNotes)
        if meeting.notesState == .structuredNotes, !sections.isEmpty {
            DisclosureGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
                        if !sections.decisions.isEmpty { section(String(localized: "Decisions"), markdown: sections.decisions) }
                        if !sections.actions.isEmpty { section(String(localized: "Tasks"), markdown: sections.actions) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                .padding(.top, GuesliTheme.spacing8)
            } label: {
                HStack {
                    Label("Since last meeting", systemImage: "clock.arrow.circlepath")
                        .font(GuesliTheme.headline())
                    Spacer()
                    Button(action: onOpen) {
                        Label(meeting.title, systemImage: "arrow.up.right")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GuesliTheme.accent)
                    .help("Open previous meeting")
                }
            }
            .foregroundStyle(GuesliTheme.textPrimary)
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, GuesliTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func section(_ title: String, markdown: String) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
            Text(title).font(GuesliTheme.captionMedium())
            Text(MarkdownInlineParser.parse(markdown))
                .font(GuesliTheme.callout())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
