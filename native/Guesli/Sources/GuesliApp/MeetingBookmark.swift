import Foundation

/// Live-meeting bookmark appended to the meeting's manual notes.
enum MeetingBookmark {
    static func line(at date: Date) -> String {
        // Same wall-clock HH:mm:ss as TranscriptFormatter, so the timestamp can link to the transcript.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return "⭐ [\(formatter.string(from: date))] Важно"
    }

    /// Returns the notes with a bookmark line appended, or nil when this second is already bookmarked.
    static func appending(to notes: String, at date: Date) -> String? {
        let bookmark = line(at: date)
        if notes.components(separatedBy: .newlines).contains(bookmark) { return nil }
        if notes.isEmpty || notes.hasSuffix("\n") { return notes + bookmark }
        return notes + "\n" + bookmark
    }
}
