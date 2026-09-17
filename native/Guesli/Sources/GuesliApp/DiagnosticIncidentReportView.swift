import SwiftUI

struct DiagnosticIncidentReportView: View {
    let incident: DiagnosticIncident
    let onOpenIssue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing20) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    Text("Diagnostic Failure Detected")
                        .font(GuesliTheme.title3())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("\(AppIdentity.displayName) detected a hard failure in \(incident.stage). You can review the anonymized report before opening a GitHub issue.")
                        .font(GuesliTheme.callout())
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                diagnosticSummaryRow("Failure", value: incident.kind.title)
                diagnosticSummaryRow("Stage", value: incident.stage)
                diagnosticSummaryRow("Model", value: incident.model)
                diagnosticSummaryRow("Error", value: "\(incident.errorDomain) \(incident.errorCode)")
                diagnosticSummaryRow("Meaning", value: incident.errorMeaning?.summary ?? "Unknown; use domain/code for lookup")
            }
            .padding(GuesliTheme.spacing12)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .stroke(Color.orange.opacity(0.24), lineWidth: 1)
            )

            Text("No transcript, audio, meeting title, calendar title, clipboard contents, screen text, API keys, auth tokens, local file paths, raw logs, or database contents are included.")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(incident.issueBody)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GuesliTheme.spacing12)
            }
            .frame(minHeight: 240)
            .background(GuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .stroke(GuesliTheme.surfaceBorder, lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("Not Now") {
                    onDismiss()
                }
                Button("Open GitHub Issue") {
                    onOpenIssue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(GuesliTheme.spacing24)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 460)
        .background(GuesliTheme.backgroundBase)
    }

    @ViewBuilder
    private func diagnosticSummaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GuesliTheme.spacing12) {
            Text(label)
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
