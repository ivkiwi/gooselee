import Testing
@testable import MuesliNativeApp

@Suite("Meeting session title selection", .muesliHermeticSupport)
struct MeetingSessionTitleTests {
    @Test("calendar event title is used when present")
    func calendarEventTitleCandidate() {
        let title = MeetingSession.calendarTitleCandidate(
            originalTitle: "April Town Hall",
            calendarEventID: "calendar-event-123"
        )

        #expect(title == "April Town Hall")
    }

    @Test("blank calendar event title falls through")
    func blankCalendarEventTitleFallsThrough() {
        let title = MeetingSession.calendarTitleCandidate(
            originalTitle: "  \n\t  ",
            calendarEventID: "calendar-event-123"
        )

        #expect(title == nil)
    }

    @Test("non-calendar meeting does not use original title as a calendar title")
    func nonCalendarMeetingFallsThrough() {
        let title = MeetingSession.calendarTitleCandidate(
            originalTitle: "Quick Note",
            calendarEventID: nil
        )

        #expect(title == nil)
    }

    @Test("non-calendar title is preserved without LLM generation")
    func fallbackPreservesUserTitle() {
        #expect(MeetingSession.fallbackTitle(originalTitle: "Quick Note") == "Quick Note")
    }

    @Test("blank title uses deterministic local fallback")
    func blankTitleUsesDeterministicFallback() {
        #expect(MeetingSession.fallbackTitle(originalTitle: "  \n ") == "Meeting")
    }
}
