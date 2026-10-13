import Foundation
import GuesliCore
import Testing
@testable import GuesliApp

@Suite("Recurring meeting context", .serialized, .guesliHermeticSupport)
struct RecurringMeetingTests {
    private func occurrence(
        start: Date,
        series: String? = "weekly%_sync",
        calendar: String = "work",
        provider: CalendarOccurrenceReference.Provider = .eventKit
    ) -> CalendarOccurrenceReference {
        CalendarOccurrenceReference(
            provider: provider, calendarID: calendar, eventID: UUID().uuidString,
            seriesID: series, originalStartTime: start
        )
    }

    private func makeStore() throws -> DictationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("guesli-recurring-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }

    private func insert(_ store: DictationStore, occurrence: CalendarOccurrenceReference) throws -> Int64 {
        try store.insertMeeting(
            title: "Weekly", calendarEventID: nil,
            startTime: occurrence.originalStartTime,
            endTime: occurrence.originalStartTime.addingTimeInterval(60),
            rawTranscript: "", formattedNotes: "## Decisions\n- Ship the fix",
            micAudioPath: nil, systemAudioPath: nil, calendarOccurrence: occurrence
        )
    }

    @Test("Series prefix includes provider, calendar and the complete series component")
    func seriesPrefix() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = occurrence(start: start)
        let next = occurrence(start: start.addingTimeInterval(100))
        #expect(first.recurringSeriesKeyPrefix == next.recurringSeriesKeyPrefix)
        #expect(first.recurringSeriesKeyPrefix?.hasSuffix("|") == true)
        #expect(first.recurringSeriesKeyPrefix != occurrence(start: start, calendar: "personal").recurringSeriesKeyPrefix)
        #expect(first.recurringSeriesKeyPrefix != occurrence(start: start, provider: .googleCalendar).recurringSeriesKeyPrefix)
        #expect(occurrence(start: start, series: nil).recurringSeriesKeyPrefix == nil)
    }

    @Test("Previous series meeting excludes deleted, equal-time, future and other series records")
    func previousSeriesMeeting() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 2_000)
        _ = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-900)))
        let expected = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-500)))
        let deleted = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-100)))
        try store.deleteMeeting(id: deleted)
        let current = try insert(store, occurrence: occurrence(start: now))
        _ = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(100)))
        _ = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-50), series: "weekly%_sync-extra"))
        _ = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-40), calendar: "personal"))
        _ = try insert(store, occurrence: occurrence(start: now.addingTimeInterval(-30), provider: .googleCalendar))
        #expect(try store.previousMeetingInCalendarSeries(occurrence(start: now), before: now)?.id == expected)
        #expect(try store.previousMeetingInCalendarSeries(beforeMeetingID: current)?.id == expected)
        #expect(try store.previousMeetingInCalendarSeries(beforeMeetingID: deleted) == nil)
        #expect(try store.previousMeetingInCalendarSeries(beforeMeetingID: -1) == nil)
        #expect(try store.previousMeetingInCalendarSeries(occurrence(start: now, series: nil), before: now) == nil)
        #expect(try store.previousMeetingInCalendarSeries(occurrence(start: now, series: "absent"), before: now) == nil)
    }

    @Test("Recurring context follows the last manual follow-up in the previous meeting thread")
    func latestFollowUpContext() throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 3_000)
        let root = try insert(store, occurrence: occurrence(start: start))
        let child = try store.createLiveMeeting(
            title: "Continuation", calendarEventID: nil,
            startTime: start.addingTimeInterval(100), followUpToID: root
        )
        try store.updateMeetingNotes(id: child, formattedNotes: "## Action Items\n- [ ] Verify the fix")
        try store.updateMeetingStatus(id: child, status: .completed)
        let next = occurrence(start: start.addingTimeInterval(1_000))
        let predecessorRecord = try RecurringMeetingContext.predecessor(in: store, occurrence: next, before: next.originalStartTime)
        let predecessor = try #require(predecessorRecord)
        #expect(predecessor.id == child)
        #expect(MeetingFollowUpPolicy.carriedContext(from: predecessor) == "## Action Items\n- [ ] Verify the fix")
        let nextID = try insert(store, occurrence: next)
        #expect(try RecurringMeetingContext.predecessor(in: store, beforeMeetingID: nextID)?.id == child)
        _ = try store.createLiveMeeting(
            title: "Future continuation", calendarEventID: nil,
            startTime: next.originalStartTime.addingTimeInterval(100), followUpToID: child
        )
        #expect(try RecurringMeetingContext.predecessor(in: store, occurrence: next, before: next.originalStartTime)?.id == child)
        #expect(try RecurringMeetingContext.predecessor(in: store, occurrence: nil, before: next.originalStartTime) == nil)
    }

    @Test("Russian template sections retain nested content and stop at peer headings")
    func russianSections() {
        let sections = PreviousMeetingNotes.extract(from: """
        ## Коротко
        - Overview
        ## Решения
        - Сохранить локальную обработку
        ### Причина
        - Конфиденциальность
        ## TODO / Исправления / Доделки
        - [ ] Проверить запись
        ## Проверка / Риски / Открытые вопросы
        - Risk
        """)
        #expect(sections.decisions == "- Сохранить локальную обработку\n### Причина\n- Конфиденциальность")
        #expect(sections.actions == "- [ ] Проверить запись")
        #expect(PreviousMeetingNotes.extract(from: "## Действия\n- [ ] Проверить").actions == "- [ ] Проверить")
    }

    @Test("English template headings, empty notes and fenced examples are handled locally")
    func englishSections() {
        let sections = PreviousMeetingNotes.extract(from: """
        ## **Decisions** ##
        - Keep local processing
        ```markdown
        ## Action Items
        - Example only
        ```
        ## Action Items
        - [ ] Verify recording
        ## Risks and Open Questions
        - Risk
        """)
        #expect(sections.decisions == "- Keep local processing\n```markdown\n## Action Items\n- Example only\n```")
        #expect(sections.actions == "- [ ] Verify recording")
        for heading in ["Actions", "Commitments", "Next Steps", "Today", "TODO / Fixes / Follow-ups"] {
            #expect(PreviousMeetingNotes.extract(from: "## \(heading)\n- Task").actions == "- Task")
        }
        #expect(PreviousMeetingNotes.extract(from: "## Decision and Next Steps\n- Continue").decisions == "- Continue")
        #expect(PreviousMeetingNotes.extract(from: "## Summary\nOnly summary").isEmpty)
        #expect(PreviousMeetingNotes.extract(from: "").isEmpty)
    }

    @Test("Preparation text includes both sections, removes checkbox syntax and bounds long Unicode notes")
    func preparationText() throws {
        let title = "Weekly"
        let notification = try #require(MeetingPreparationNotification.make(
            title: title, notes: "## Decisions\n- **Keep local processing**\n## Action Items\n- [ ] `Verify` recording"
        ))
        #expect(notification.title == String(localized: "Before meeting: \(title)"))
        #expect(notification.body.contains(String(localized: "Tasks:")))
        #expect(notification.body.contains(String(localized: "Decisions:")))
        #expect(notification.body.contains("- Verify recording"))
        #expect(notification.body.contains("- Keep local processing"))
        #expect(!notification.body.contains("[ ]"))
        let long = try #require(MeetingPreparationNotification.make(
            title: "Weekly", notes: "## Actions\n" + String(repeating: "Проверить 🪿 ", count: 100) + "\n## Decisions\nKeep it",
            maxBodyLength: 100
        ))
        #expect(long.body.count <= 100)
        #expect(long.body.contains("…"))
        #expect(long.body.contains("Keep it"))
        #expect(MeetingPreparationNotification.make(title: "Weekly", notes: " \n ") == nil)
        #expect(MeetingPreparationNotification.make(title: "Weekly", notes: "Notes", maxBodyLength: 0) == nil)
        #expect(MeetingPreparationNotification.make(title: "Weekly", notes: "Notes")?.body == "Notes")
    }

    @Test("Preparation candidates include recurring events without join links and respect the 15-minute boundary")
    func preparationCandidates() {
        let now = Date(timeIntervalSince1970: 4_000)
        func event(_ id: String, delay: TimeInterval, recurring: Bool = true, allDay: Bool = false) -> UnifiedCalendarEvent {
            let start = now.addingTimeInterval(delay)
            return UnifiedCalendarEvent(
                id: id, title: "Weekly", startDate: start, endDate: start.addingTimeInterval(600),
                isAllDay: allDay, source: .eventKit,
                calendarOccurrence: occurrence(start: start, series: recurring ? "weekly" : nil)
            )
        }
        let events = [
            event("due", delay: 900), event("soon", delay: 900 - 89), event("late", delay: 900 - 90),
            event("future", delay: 1_800), event("single", delay: 900, recurring: false),
            event("hidden", delay: 900), event("all-day", delay: 900, allDay: true),
            event("started", delay: -10), event("distant", delay: 20 * 60 * 60)
        ]
        #expect(ScheduledMeetingNotificationPolicy.preparationCandidates(
            from: events, now: now, hiddenEventIDs: ["hidden"]
        ).map(\.id) == ["soon", "due", "future"])
    }

    @Test("Preparation reminders default on for old settings and persist an explicit off value")
    func preparationSetting() throws {
        let legacy = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(legacy.showMeetingPreparationNotifications)
        var disabled = AppConfig()
        disabled.showMeetingPreparationNotifications = false
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(disabled))
        #expect(!restored.showMeetingPreparationNotifications)
    }
}
