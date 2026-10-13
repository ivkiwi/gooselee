import Testing
@testable import GuesliApp

@Suite("Meeting speaker rename", .guesliHermeticSupport)
struct MeetingSpeakerRenameTests {
    @Test("only the exact label in timestamped lines is replaced")
    func onlyExactLabelIsReplaced() {
        let transcript = """
        [10:00:00] Speaker 1: Speaker 1: is mentioned in text.
        [10:00:04] You: Speaker 1 said hi.
        Speaker 1: plain line without timestamp.
        [10:00:09] Speaker 1: Bye.
        """

        let renamed = MeetingSpeakerRename.rename("Speaker 1", to: "  Анна  ", in: transcript)

        #expect(renamed == """
        [10:00:00] Анна: Speaker 1: is mentioned in text.
        [10:00:04] You: Speaker 1 said hi.
        Speaker 1: plain line without timestamp.
        [10:00:09] Анна: Bye.
        """)
    }

    @Test("Speaker 1 and Speaker 10 are not confused")
    func similarLabelsAreNotConfused() {
        let transcript = """
        [10:00:00] Speaker 1: One.
        [10:00:01] Speaker 10: Ten.
        """

        #expect(MeetingSpeakerRename.rename("Speaker 1", to: "Анна", in: transcript) == """
        [10:00:00] Анна: One.
        [10:00:01] Speaker 10: Ten.
        """)
        #expect(MeetingSpeakerRename.rename("Speaker 10", to: "Борис", in: transcript) == """
        [10:00:00] Speaker 1: One.
        [10:00:01] Борис: Ten.
        """)
    }

    @Test("names with a colon are rejected because they break the label format")
    func nameWithColonIsRejected() {
        let transcript = "[10:00:00] Speaker 1: Hi."

        #expect(MeetingSpeakerRename.validatedName("Анна: PM") == nil)
        #expect(MeetingSpeakerRename.rename("Speaker 1", to: "Анна: PM", in: transcript) == nil)
    }

    @Test("empty or whitespace-only names are rejected")
    func emptyNameIsRejected() {
        let transcript = "[10:00:00] Speaker 1: Hi."

        #expect(MeetingSpeakerRename.rename("Speaker 1", to: "", in: transcript) == nil)
        #expect(MeetingSpeakerRename.rename("Speaker 1", to: "   \n", in: transcript) == nil)
    }

    @Test("renamed labels still parse as speakers in the transcript view")
    func renamedLabelParsesAsSpeaker() throws {
        let renamed = try #require(MeetingSpeakerRename.rename("Speaker 1", to: "Анна", in: "[10:00:00] Speaker 1: Note: hi."))
        let message = try #require(TranscriptChatMessage.messages(from: renamed).first)

        #expect(message.speaker == "Анна")
        #expect(message.text == "Note: hi.")
    }
}
