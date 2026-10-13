import Testing
import Foundation
@testable import GuesliApp

@Suite("MeetingBookmark", .guesliHermeticSupport)
struct MeetingBookmarkTests {
    private func date(hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 1
        components.hour = hour; components.minute = minute; components.second = second
        return Calendar.current.date(from: components)!
    }

    @Test("formats the line with the transcript wall-clock timestamp")
    func formatsLine() {
        #expect(MeetingBookmark.line(at: date(hour: 9, minute: 5, second: 7)) == "⭐ [09:05:07] Важно")
    }

    @Test("appends on its own line")
    func appendsOnOwnLine() {
        let at = date(hour: 14, minute: 31, second: 5)
        #expect(MeetingBookmark.appending(to: "", at: at) == "⭐ [14:31:05] Важно")
        #expect(MeetingBookmark.appending(to: "Agenda", at: at) == "Agenda\n⭐ [14:31:05] Важно")
        #expect(MeetingBookmark.appending(to: "Agenda\n", at: at) == "Agenda\n⭐ [14:31:05] Важно")
    }

    @Test("skips a repeated press within the same second")
    func skipsSameSecondDuplicate() {
        let first = date(hour: 14, minute: 31, second: 5)
        let notes = MeetingBookmark.appending(to: "Agenda", at: first)!
        #expect(MeetingBookmark.appending(to: notes, at: first.addingTimeInterval(0.4)) == nil)
        #expect(MeetingBookmark.appending(to: notes, at: first.addingTimeInterval(1))
            == "Agenda\n⭐ [14:31:05] Важно\n⭐ [14:31:06] Важно")
    }

    @Test("bookmark hotkey must differ from active meeting shortcuts")
    func bookmarkHotkeyConflicts() {
        let bookmark = HotkeyConfig.meetingBookmarkDefault
        #expect(ShortcutHotkeyPolicy.validateMeetingBookmarkHotkey(
            bookmark, dictationHotkey: .default, meetingRecordingHotkey: bookmark, isMeetingRecordingEnabled: true
        ).didUpdate == false)
        #expect(ShortcutHotkeyPolicy.validateMeetingBookmarkHotkey(
            bookmark, dictationHotkey: .default, meetingRecordingHotkey: bookmark, isMeetingRecordingEnabled: false
        ).didUpdate)
        #expect(ShortcutHotkeyPolicy.validateMeetingBookmarkHotkey(
            .default, dictationHotkey: .default, meetingRecordingHotkey: .meetingRecordingDefault, isMeetingRecordingEnabled: false
        ).didUpdate == false)
    }
}
