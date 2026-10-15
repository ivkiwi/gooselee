import AppKit
import GuesliCore
import SwiftUI

struct MeetingArchiveChatView: View {
    let appState: AppState
    let controller: GuesliController
    let scope: ArchiveChatScope
    @Environment(\.dismiss) private var dismiss
    @State private var model = ArchiveChatModel()
    @State private var draft = ""
    @State private var useFolder = false
    @State private var useDates = false
    @State private var fromDate = Date()
    @State private var throughDate = Date()

    private var effectiveScope: ArchiveChatScope {
        guard scope.meetingID == nil else { return scope }
        var result = scope
        result.folderID = useFolder ? appState.selectedFolderID : nil
        if useDates {
            result.fromDate = Calendar.current.startOfDay(for: fromDate)
            result.toDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: throughDate))
        } else {
            result.fromDate = nil
            result.toDate = nil
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
            HStack {
                Text("Ask meetings").font(GuesliTheme.title2())
                Spacer()
                Button("New chat") { model.newChat(); draft = "" }
                Button("Close") { model.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            scopeControls
            Text("Uses the selected summary backend. Conversation stays in memory until this chat closes.")
                .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
                    ForEach(model.turns.filter { $0.question != model.question || $0.answer != model.answer }) { turn in
                        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                            Text(turn.question).font(GuesliTheme.headline())
                            Text(turn.answer).font(GuesliTheme.body()).textSelection(.enabled)
                            ForEach(turn.sources) { source in
                                sourceLink(source)
                            }
                        }
                    }
                    if !model.question.isEmpty {
                        Text(model.question).font(GuesliTheme.headline())
                    }
                    if model.isRunning {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Reading selected sources…")
                            Spacer()
                            Button("Stop", action: model.cancel)
                        }
                    }
                    if model.isIncomplete {
                        Label("Incomplete answer. Retry to request a complete answer.", systemImage: "exclamationmark.circle")
                            .font(GuesliTheme.caption())
                    }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(GuesliTheme.textPrimary)
                    }
                    if !model.answer.isEmpty {
                        Text(model.answer).font(GuesliTheme.body()).textSelection(.enabled)
                    }
                    if !model.invalidCitations.isEmpty {
                        Label("Citation check failed. The answer contains missing or unknown source IDs.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(GuesliTheme.recording)
                            .font(GuesliTheme.callout())
                    }
                    if !model.sources.isEmpty {
                        sourceList
                        Text(model.limited
                             ? String(localized: "Only part of the matching results fit. This answer does not cover the whole archive.")
                             : String(localized: "The answer uses a bounded literal-word search, not an exhaustive archive review."))
                            .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            TextField("Ask about a topic, decision or action…", text: $draft, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { ask(draft) }
            HStack {
                if !model.question.isEmpty {
                    Button("Retry") { ask(model.question) }
                        .disabled(model.isRunning)
                }
                Spacer()
                Button("Ask question") { ask(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validDates)
            }
        }
        .padding(GuesliTheme.spacing24)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 600, idealHeight: 740)
        .background(GuesliTheme.backgroundBase)
        .foregroundStyle(GuesliTheme.textPrimary)
        .onAppear {
            useFolder = scope.folderID != nil
            useDates = scope.fromDate != nil || scope.toDate != nil
            fromDate = scope.fromDate ?? Date()
            throughDate = scope.toDate.flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) } ?? Date()
        }
        .onChange(of: effectiveScope) { _, _ in model.newChat() }
        .onDisappear { model.newChat() }
    }

    private var validDates: Bool { !useDates || Calendar.current.startOfDay(for: fromDate) <= Calendar.current.startOfDay(for: throughDate) }

    @ViewBuilder private var scopeControls: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack {
                Text(appState.selectedMeetingSummaryBackend.label).font(GuesliTheme.headline())
                Spacer()
                if scope.meetingID != nil {
                    Label("This meeting", systemImage: "doc.text")
                } else {
                    Picker("Search scope", selection: $useFolder) {
                        Text("All meetings").tag(false)
                        if appState.selectedFolderID != nil { Text("Current folder").tag(true) }
                    }
                    .fixedSize()
                }
            }
            if scope.meetingID == nil {
                HStack {
                    Toggle("Date range", isOn: $useDates).toggleStyle(.checkbox)
                    if useDates {
                        DatePicker("From", selection: $fromDate, displayedComponents: .date)
                        DatePicker("Through", selection: $throughDate, displayedComponents: .date)
                    }
                }
                if !validDates {
                    Text("The end date must be on or after the start date.")
                        .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.recording)
                }
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            Text("Sources sent to AI").font(GuesliTheme.headline())
            ForEach(model.sources) { source in
                HStack(alignment: .top, spacing: GuesliTheme.spacing8) {
                    Toggle(isOn: Binding(
                        get: { !model.excludedMeetingIDs.contains(source.meetingID) },
                        set: { included in
                            if included { model.excludedMeetingIDs.remove(source.meetingID) }
                            else { model.excludedMeetingIDs.insert(source.meetingID) }
                        }
                    )) { EmptyView() }
                    .labelsHidden().toggleStyle(.checkbox)
                    .disabled(model.isRunning)
                    .accessibilityLabel(Text("Include meeting in retry"))
                    sourceLink(source)
                    Spacer(minLength: 0)
                }
            }
            Text("Uncheck a meeting, then Retry to answer without it.")
                .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
        }
    }

    private func sourceLink(_ source: ArchiveChatSource) -> some View {
        let fresh = try? controller.archiveChatMeeting(id: source.meetingID)
        let availability = source.availability(in: fresh)
        return Button {
            controller.showArchiveChatSource(source)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("[\(source.id)] \(source.title)").multilineTextAlignment(.leading)
                Text("\(source.date) · \(source.kind.label)")
                    .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
                if availability != .current {
                    Text(availability == .stale ? String(localized: "Source changed — link is stale") : String(localized: "Source unavailable"))
                        .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.recording)
                } else if source.staleSummary {
                    Text("Historical summary — current transcript unavailable")
                        .font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(availability == .unavailable)
    }

    private func ask(_ text: String) {
        guard validDates else { return }
        model.ask(text, scope: effectiveScope, config: appState.config,
                  candidates: controller.archiveChatCandidates, freshMeeting: controller.archiveChatMeeting)
    }
}

struct ArchiveChatSourceView: View {
    let source: ArchiveChatSource
    let meeting: MeetingRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            Text("Source [\(source.id)] · \(source.title)").font(GuesliTheme.headline())
            Text(source.kind.label).font(GuesliTheme.caption()).foregroundStyle(GuesliTheme.textSecondary)
            switch source.availability(in: meeting) {
            case .current:
                if let meeting {
                    ArchiveChatHighlightedText(text: source.kind.text(in: meeting), range: source.range)
                        .frame(minHeight: 180, idealHeight: 260)
                }
            case .stale:
                Label("Source changed. The old fragment cannot be highlighted in the current text. Ask again to refresh sources.", systemImage: "exclamationmark.triangle")
            case .unavailable:
                Label("Source unavailable. The meeting may have been deleted.", systemImage: "exclamationmark.triangle")
            }
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
    }
}

private struct ArchiveChatHighlightedText: NSViewRepresentable {
    let text: String
    let range: NSRange

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.frame = scroll.contentView.bounds
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let content = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor
        ])
        if NSMaxRange(range) <= content.length {
            content.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45), range: range)
        }
        view.textStorage?.setAttributedString(content)
        view.setSelectedRange(range)
        view.scrollRangeToVisible(range)
    }
}
