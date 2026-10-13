import Foundation
import Testing
@testable import GuesliApp

@Suite("Transcript recording seek", .guesliHermeticSupport)
struct TranscriptRecordingSeekTests {
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test("clock timestamps cross midnight")
    func crossesMidnight() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-12T23:55:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: "00:05:00", meetingStart: start, duration: 1_200, timeZone: utc
        ) == 600)
    }

    @Test("clock timestamps preserve elapsed hours")
    func preservesHours() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:15:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: "12:45:30", meetingStart: start, duration: 10_000, timeZone: utc
        ) == 9_030)
    }

    @Test("timestamps use the transcript time zone")
    func usesTranscriptTimeZone() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:00:00Z"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 3 * 3_600))
        #expect(TranscriptRecordingSeek.offset(
            for: "13:02:00", meetingStart: start, duration: 180, timeZone: timeZone
        ) == 120)
    }

    @Test("the first truncated second seeks to the beginning")
    func truncatesFractionalStart() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:00:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: "10:00:00", meetingStart: start.addingTimeInterval(0.75), duration: 60, timeZone: utc
        ) == 0)
    }

    @Test("malformed clock timestamps are rejected", arguments: [
        "", "garbage", "[10:00:00]", "1:00:00", "10:00", "10:00:00 text",
        " 10:00:00", "10:00:00\n", "24:00:00", "10:60:00", "10:00:60",
        "-1:00:00", "aa:00:00", "１０:00:00"
    ])
    func rejectsMalformedTimestamp(_ timestamp: String) throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:00:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: timestamp, meetingStart: start, duration: 60, timeZone: utc
        ) == nil)
    }

    @Test("timestamps outside the recording are rejected")
    func rejectsOutOfBoundsTimestamp() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:00:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: "09:59:59", meetingStart: start, duration: 60, timeZone: utc
        ) == nil)
        #expect(TranscriptRecordingSeek.offset(
            for: "10:01:01", meetingStart: start, duration: 60, timeZone: utc
        ) == nil)
        #expect(TranscriptRecordingSeek.offset(
            for: "10:01:00", meetingStart: start, duration: 60, timeZone: utc
        ) == 60)
        #expect(TranscriptRecordingSeek.offset(
            for: "00:00:00", meetingStart: start, duration: 60, timeZone: utc
        ) == nil)
    }

    @Test("invalid recording bounds are rejected", arguments: [-1.0, Double.nan, Double.infinity])
    func rejectsInvalidDuration(_ duration: TimeInterval) throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-13T10:00:00Z"))
        #expect(TranscriptRecordingSeek.offset(
            for: "10:00:00", meetingStart: start, duration: duration, timeZone: utc
        ) == nil)
    }
}
