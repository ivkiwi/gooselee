import Foundation
import GuesliCore

enum RecurringMeetingContext {
    static func predecessor(
        in store: DictationStore,
        occurrence: CalendarOccurrenceReference?,
        before startTime: Date
    ) throws -> MeetingRecord? {
        guard let occurrence,
              let previous = try store.previousMeetingInCalendarSeries(occurrence, before: startTime) else { return nil }
        return try latestPredecessor(in: store, previous: previous, before: startTime)
    }

    static func predecessor(in store: DictationStore, beforeMeetingID meetingID: Int64) throws -> MeetingRecord? {
        guard let previous = try store.previousMeetingInCalendarSeries(beforeMeetingID: meetingID),
              let current = try store.meeting(id: meetingID),
              let startTime = ISO8601DateFormatter().date(from: current.startTime) else { return nil }
        return try latestPredecessor(in: store, previous: previous, before: startTime)
    }

    private static func latestPredecessor(in store: DictationStore, previous: MeetingRecord, before startTime: Date) throws -> MeetingRecord {
        let ids = try store.meetingThreadIDs(containing: previous.id)
        let formatter = ISO8601DateFormatter()
        for id in ids.reversed() {
            if let candidate = try store.meeting(id: id),
               let candidateStart = formatter.date(from: candidate.startTime), candidateStart < startTime {
                return candidate
            }
        }
        return previous
    }
}
