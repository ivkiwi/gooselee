import Foundation
import FluidAudio
import GuesliCore
import Testing
@testable import GuesliApp

@Suite("Speaker provenance", .guesliHermeticSupport)
struct SpeakerProvenanceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func sameNameTranscript() -> (transcript: String, attribution: MeetingSpeakerAttribution) {
        TranscriptFormatter.mergeAttributed(
            micSegments: [],
            systemSegments: [
                SpeechSegment(start: 0, end: 1, text: "First person's words."),
                SpeechSegment(start: 1, end: 2, text: "Second person's words.")
            ],
            diarizationSegments: [
                TimedSpeakerSegment(speakerId: "first", embedding: [], startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1),
                TimedSpeakerSegment(speakerId: "second", embedding: [], startTimeSeconds: 1, endTimeSeconds: 2, qualityScore: 1)
            ],
            speakerNameMap: ["first": "Alex", "second": "Alex"], meetingStart: start
        )
    }

    @Test("Summary input mismatch survives result overrides")
    func summaryInputMismatchSurvivesOverrides() {
        let result = MeetingSessionResult(
            title: "Meeting", originalTitle: "Meeting", calendarEventID: nil,
            startTime: start, endTime: start.addingTimeInterval(2), durationSeconds: 2,
            rawTranscript: "Cleaned words", summaryInputMatchesTranscript: false,
            formattedNotes: "Summary from raw words", retainedRecordingURL: nil,
            retainedRecordingError: nil, systemRecordingURL: nil,
            templateSnapshot: MeetingTemplates.auto.snapshot
        )
        #expect(!result.summaryInputMatchesTranscript)
        #expect(!result.overriding(durationSeconds: 3).summaryInputMatchesTranscript)
        #expect(!result.overriding(rawTranscript: "Combined transcript").summaryInputMatchesTranscript)
    }

    @Test("Equal display names retain independent turns and manual corrections")
    func sameNamesStayIndependent() throws {
        let result = sameNameTranscript()
        #expect(result.transcript.components(separatedBy: "\n").count == 2)
        #expect(result.attribution.speakers.count == 2)
        #expect(result.attribution.speakers.allSatisfy { $0.source == .googleMeet })
        let first = try #require(result.attribution.speaker(atLine: 0))
        let second = try #require(result.attribution.speaker(atLine: 1))
        #expect(first.id != second.id)
        let corrected = try #require(MeetingSpeakerRename.rename(
            speakerID: first.id, to: "Anna", in: result.transcript, attribution: result.attribution
        ))
        #expect(corrected.transcript.components(separatedBy: "\n")[0].contains("] Anna: First person's words."))
        #expect(corrected.transcript.components(separatedBy: "\n")[1].contains("] Alex: Second person's words."))
        #expect(corrected.attribution.speaker(atLine: 0)?.source == .user)
        #expect(corrected.attribution.speaker(atLine: 1)?.source == .googleMeet)
        #expect(MeetingSpeakerRename.rename(speakerID: first.id, to: "Anna", in: corrected.transcript, attribution: corrected.attribution) == nil)
    }

    @Test("Attribution roundtrip preserves sources and contains no bridge payload")
    func durableDisplayOnlyMetadata() throws {
        let result = sameNameTranscript()
        let json = try #require(result.attribution.json)
        let decoded = try #require(MeetingSpeakerAttribution.decode(json))
        #expect(decoded == result.attribution)
        #expect(decoded.validated(for: result.transcript) != nil)
        #expect(!json.contains("observedAt"))
        #expect(!json.contains("First person's words"))
        #expect(!json.contains("emailAddress"))
    }

    @Test("New ASR generation never accepts a former speaker identity")
    func generationDoesNotTransferIdentity() throws {
        let before = sameNameTranscript()
        let after = sameNameTranscript()
        let previousID = try #require(before.attribution.speaker(atLine: 0)?.id)
        #expect(before.attribution.generationID != after.attribution.generationID)
        #expect(MeetingSpeakerRename.rename(speakerID: previousID, to: "Anna", in: after.transcript, attribution: after.attribution) == nil)
    }

    @Test("Unmatched and legacy names remain unknown, only a corrected legacy speaker becomes manual")
    func legacyIsUnknown() throws {
        let transcript = "[10:00:00] Anna: First.\n[10:00:01] Boris: Second."
        let legacy = MeetingSpeakerAttribution.legacy(transcript: transcript)
        #expect(legacy.speakers.allSatisfy { $0.source == .unknown })
        #expect(legacy == MeetingSpeakerAttribution.legacy(transcript: transcript))
        let id = try #require(legacy.speaker(atLine: 0)?.id)
        let corrected = try #require(MeetingSpeakerRename.rename(speakerID: id, to: "Anya", in: transcript, attribution: legacy))
        #expect(corrected.attribution.speaker(atLine: 0)?.source == .user)
        #expect(corrected.attribution.speaker(atLine: 1)?.source == .unknown)
        let unnamed = TranscriptFormatter.mergeAttributed(
            micSegments: [], systemSegments: [SpeechSegment(start: 0, end: 1, text: "Speech")],
            diarizationSegments: [TimedSpeakerSegment(speakerId: "first", embedding: [], startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1)],
            meetingStart: start
        )
        #expect(unnamed.attribution.speakers.first?.displayName == "Speaker 1")
        #expect(unnamed.attribution.speakers.first?.source == .unknown)
    }

    @Test("Cleanup preserves ordinary word edits and blank lines, rejects ambiguous turn rewrites")
    func cleanupRebasesSafely() throws {
        let result = sameNameTranscript()
        let cleaned = result.transcript.replacingOccurrences(of: "First person's words.", with: "Corrected first words.")
            .replacingOccurrences(of: "\n", with: "\n\n")
        let rebased = try #require(result.attribution.rebased(from: result.transcript, to: cleaned))
        #expect(rebased.validated(for: cleaned) != nil)
        #expect(rebased.speaker(atLine: 0)?.id == result.attribution.speaker(atLine: 0)?.id)
        #expect(rebased.speaker(atLine: 1) == nil)
        #expect(rebased.speaker(atLine: 2)?.id == result.attribution.speaker(atLine: 1)?.id)
        let merged = result.transcript.components(separatedBy: "\n")[0]
        #expect(result.attribution.rebased(from: result.transcript, to: merged) == nil)
        #expect(result.attribution.rebased(from: result.transcript, to: result.transcript.replacingOccurrences(of: "] Alex:", with: "] Other:")) == nil)
    }

    @Test("Shifted metadata cannot rename unrelated lines; UI uses physical line indices")
    func shiftedMetadataAndUI() throws {
        let result = sameNameTranscript()
        let shifted = "\n" + result.transcript
        #expect(result.attribution.validated(for: shifted) == nil)
        let id = try #require(result.attribution.speaker(atLine: 0)?.id)
        #expect(MeetingSpeakerRename.rename(speakerID: id, to: "Anna", in: shifted, attribution: result.attribution) == nil)
        let rebased = try #require(result.attribution.rebased(from: result.transcript, to: shifted))
        let messages = TranscriptChatMessage.messages(from: shifted, attribution: rebased)
        #expect(messages.count == 2)
        #expect(messages[0].speakerID == id)
        #expect(messages[1].speakerID != id)
        #expect(messages[0].speakerSource == .googleMeet)
    }
}
