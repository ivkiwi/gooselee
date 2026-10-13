import Testing
import Foundation
import GuesliCore
@testable import GuesliApp

@Suite("MeetingFollowUpEmail", .guesliHermeticSupport)
struct MeetingFollowUpEmailTests {
    @Test("source material includes summary, written notes and transcript")
    func sourceMaterialIncludesAllInputs() {
        let source = MeetingFollowUpEmail.sourceMaterial(
            summary: "  ## Решения\n- Запускаем пилот  ",
            manualNotes: "Позвонить юристам",
            transcript: "Иван: давайте запускать пилот"
        )

        #expect(source.hasPrefix("Meeting summary:\n## Решения\n- Запускаем пилот\n\n"))
        #expect(source.contains("Notes typed by the user during the meeting:\nПозвонить юристам"))
        #expect(source.contains("Transcript excerpt (to confirm the meeting language and details):\nИван: давайте запускать пилот"))
    }

    @Test("source material skips empty notes and transcript")
    func sourceMaterialSkipsEmptySections() {
        let source = MeetingFollowUpEmail.sourceMaterial(summary: "Summary", manualNotes: " \n", transcript: "")

        #expect(source == "Meeting summary:\nSummary")
    }

    @Test("long transcript is reduced to an excerpt")
    func longTranscriptIsExcerpted() {
        let transcript = String(repeating: "слово ", count: 5_000)
        let source = MeetingFollowUpEmail.sourceMaterial(summary: "Summary", manualNotes: "", transcript: transcript)

        #expect(source.contains("Opening excerpt:"))
        #expect(source.count < 6_000)
    }

    @Test("email template replaces the meeting notes instructions")
    func emailTemplateReplacesNotesInstructions() {
        let instructions = MeetingSummaryClient.summaryInstructions(for: MeetingFollowUpEmail.template)

        #expect(instructions == MeetingFollowUpEmail.template.prompt)
        #expect(!instructions.contains("meeting notes assistant"))
        #expect(MeetingSummaryClient.summaryInstructions(for: MeetingTemplates.auto.snapshot).contains("meeting notes assistant"))
    }
}
