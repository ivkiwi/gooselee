import Foundation
import GuesliCore

enum TranscriptRecordingSeek {
    static func offset(
        for timestamp: String,
        meetingStart: Date,
        duration: TimeInterval,
        timeZone: TimeZone = .current
    ) -> TimeInterval? {
        let bytes = Array(timestamp.utf8)
        guard bytes.count == 8, bytes[2] == 58, bytes[5] == 58,
              [0, 1, 3, 4, 6, 7].allSatisfy({ bytes[$0] >= 48 && bytes[$0] <= 57 }),
              duration.isFinite, duration >= 0,
              meetingStart.timeIntervalSince1970.isFinite else { return nil }

        let hour = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minute = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        let second = Int(bytes[6] - 48) * 10 + Int(bytes[7] - 48)
        guard hour < 24, minute < 60, second < 60 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // TranscriptFormatter drops fractional seconds; retain the first second of audio.
        let start = Date(timeIntervalSince1970: meetingStart.timeIntervalSince1970.rounded(.down))
        // shortcut: clock labels identify the first occurrence; store dated offsets for recordings over 24 hours.
        guard let date = calendar.nextDate(
            after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: second),
            matchingPolicy: .strict
        ) else { return nil }

        let offset = date.timeIntervalSince(start)
        return offset >= 0 && offset <= duration ? offset : nil
    }

    static func unavailableReason(for meeting: MeetingRecord) -> String? {
        guard let path = meeting.savedRecordingPath,
              FileManager.default.fileExists(atPath: path) else {
            return String(localized: "Recording not saved — enable recording retention in Settings")
        }
        // shortcut: resumed transcripts have no recording-part map; enable seeking when that map is persisted.
        if meeting.rawTranscript.contains("— Resumed —") {
            return String(localized: "Seeking unavailable for a resumed meeting")
        }
        guard ISO8601DateFormatter().date(from: meeting.startTime) != nil else {
            return String(localized: "Meeting start time unavailable")
        }
        return nil
    }
}

struct MeetingRecordingSeekRequest: Equatable {
    let id = UUID()
    let meetingID: Int64
    let recordingPath: String
    let meetingStart: Date
    let timestamp: String

    init?(meeting: MeetingRecord, timestamp: String) {
        guard let path = meeting.savedRecordingPath,
              let start = ISO8601DateFormatter().date(from: meeting.startTime) else { return nil }
        meetingID = meeting.id
        recordingPath = path
        meetingStart = start
        self.timestamp = timestamp
    }
}
