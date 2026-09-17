import SwiftUI
import GuesliCore

struct DictationRowView: View {
    let record: DictationRecord
    let timeOnly: String
    let onCopy: () -> Void
    var onCopyTrace: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    @State private var isExpanded = false

    private var isComputerUseCommand: Bool {
        record.source == "cua"
    }

    private var syncOriginBadgeLabel: String? {
        SyncOriginDisplay.badgeLabel(forDictationSource: record.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing20) {
                Text(timeOnly)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .frame(width: 80, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                    HStack(alignment: .firstTextBaseline, spacing: GuesliTheme.spacing8) {
                        if isComputerUseCommand {
                            Text("CUA")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(GuesliTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(GuesliTheme.accentSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let syncOriginBadgeLabel {
                            SyncOriginBadge(label: syncOriginBadgeLabel)
                        }

                        Text(record.rawText)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(GuesliTheme.textPrimary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if let trace = record.computerUseTrace {
                            Text(Self.displayFinalStatus(trace.finalStatus))
                                .font(GuesliTheme.captionMedium())
                                .foregroundStyle(statusColor(trace.finalStatus))
                        }
                    }

                    if isExpanded, let trace = record.computerUseTrace {
                        computerUseTraceView(trace)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if record.computerUseTrace != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GuesliTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    if record.computerUseTrace != nil, let onCopyTrace {
                        Button(action: onCopyTrace) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.system(size: 12))
                                .foregroundStyle(GuesliTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CUA trace")
                    }

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(GuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    if onDelete != nil {
                        Button { showDeleteConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(isHovered || isExpanded || record.computerUseTrace != nil ? 1 : 0)
            }
        }
        .padding(.horizontal, GuesliTheme.spacing20)
        .padding(.vertical, GuesliTheme.spacing16)
        .background(isHovered ? GuesliTheme.backgroundHover : GuesliTheme.backgroundRaised)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .alert("Delete Dictation", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this dictation? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func computerUseTraceView(_ trace: ComputerUseTraceRecord) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                ForEach(trace.events) { event in
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                        HStack(spacing: GuesliTheme.spacing8) {
                            Text(event.step.map { "Step \($0)" } ?? "Run")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(GuesliTheme.textTertiary)
                                .frame(width: 48, alignment: .leading)

                            Text(event.title)
                                .font(GuesliTheme.captionMedium())
                                .foregroundStyle(GuesliTheme.textSecondary)

                            if let status = ComputerUseTraceFormatter.displayStatus(for: event) {
                                Text(status)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(statusColor(status))
                            }
                        }

                        Text(event.body)
                            .font(.system(size: 12, weight: .regular, design: event.kind == "model_output" ? .monospaced : .default))
                            .foregroundStyle(GuesliTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .padding(.top, GuesliTheme.spacing4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "executed":
            return GuesliTheme.success
        case "confirm", "needsconfirmation":
            return GuesliTheme.transcribing
        case "timed_out", "timedout":
            return GuesliTheme.transcribing
        case "failed", "unsupported":
            return GuesliTheme.recording
        default:
            return GuesliTheme.textTertiary
        }
    }

    private static func displayFinalStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done":
            return "Done"
        case "timed_out", "timedout":
            return "Timed out"
        case "failed", "fail":
            return "Failed"
        case "confirm", "needsconfirmation", "needs_confirmation":
            return "Confirm"
        case "cancelled", "canceled":
            return "Cancelled"
        default:
            return status.capitalized
        }
    }
}
