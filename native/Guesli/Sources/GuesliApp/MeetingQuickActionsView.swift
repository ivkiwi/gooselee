import AppKit
import GuesliCore
import SwiftUI

struct MeetingQuickActionsView: View {
    let appState: AppState
    var meeting: MeetingRecord? = nil
    var compact = false
    @State private var didCopy = false

    private var model: MeetingQuickActionModel { appState.meetingQuickActions }
    private var meetingID: Int64? { meeting?.id ?? appState.liveMeetingTranscriptOwnerID }
    private var showsResult: Bool { meetingID != nil && model.meetingID == meetingID }

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(spacing: GuesliTheme.spacing8) {
                ForEach(MeetingQuickAction.allCases) { action in
                    Button(action.title) { run(action) }
                        .disabled(meetingID == nil || model.isRunning)
                        .help(action == .catchUp ? String(localized: "Review the last two minutes") : action.title)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(GuesliTheme.caption())

            if model.isRunning {
                HStack(spacing: GuesliTheme.spacing8) {
                    ProgressView().controlSize(.small)
                    Text(showsResult ? String(localized: "Preparing an answer…") : String(localized: "AI is processing another meeting…"))
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                    Spacer(minLength: 0)
                    Button("Cancel", action: model.cancel)
                        .buttonStyle(.plain)
                }
            }

            if showsResult, let error = model.errorMessage {
                Text(error)
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsResult, !model.answer.isEmpty {
                HStack {
                    Text(model.action?.title ?? String(localized: "AI answer"))
                        .font(GuesliTheme.caption().weight(.semibold))
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.answer, forType: .string)
                        didCopy = true
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help(didCopy ? String(localized: "Copied") : String(localized: "Copy answer"))
                    .accessibilityLabel(Text("Copy answer"))
                    Button {
                        model.reset(for: meetingID)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Close answer")
                    .accessibilityLabel(Text("Close answer"))
                }
                MeetingNotesView(markdown: model.answer)
                    .frame(height: compact ? 110 : 200)
            }
        }
        .onChange(of: meetingID) { oldID, _ in
            if let oldID { model.reset(for: oldID) }
        }
        .onChange(of: model.answer) { _, _ in didCopy = false }
        .onDisappear {
            if let meetingID, model.meetingID == meetingID, model.isRunning { model.cancel() }
        }
    }

    private func run(_ action: MeetingQuickAction) {
        guard let meetingID else { return }
        let isLive = appState.liveMeetingTranscriptOwnerID == meetingID
        let sourceMeeting = meeting ?? model.meetingRecordProvider?(meetingID)
        let transcript = MeetingQuickActionTranscript.sourceText(
            for: action, persisted: sourceMeeting?.rawTranscript ?? "",
            live: isLive ? appState.liveMeetingTranscript : nil
        )
        model.run(
            action, meetingID: meetingID, transcript: transcript,
            meetingTitle: sourceMeeting?.title ?? "", config: appState.config,
            isChatGPTAuthenticated: appState.isChatGPTAuthenticated, isLive: isLive,
            isCurrentMeeting: { [weak appState] in
                guard let appState else { return false }
                return isLive ? appState.liveMeetingTranscriptOwnerID == meetingID : appState.selectedMeetingID == meetingID
            }
        )
    }
}
