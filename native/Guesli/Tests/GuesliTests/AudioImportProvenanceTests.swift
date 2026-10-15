import Foundation
import FluidAudio
import Testing
import GuesliCore
@testable import GuesliApp

@Suite("Imported audio speaker provenance", .guesliHermeticSupport)
struct AudioImportProvenanceTests {
    @Test("Imported speaker identities survive independent same-name corrections")
    func importedSpeakerIdentity() throws {
        let transcription = SpeechTranscriptionResult(text: "First decision. Second decision.", segments: [
            SpeechSegment(start: 0, end: 2, text: "First decision."),
            SpeechSegment(start: 5, end: 7, text: "Second decision.")
        ])
        let diarization = [
            TimedSpeakerSegment(speakerId: "first", embedding: [], startTimeSeconds: 0, endTimeSeconds: 2, qualityScore: 1),
            TimedSpeakerSegment(speakerId: "second", embedding: [], startTimeSeconds: 5, endTimeSeconds: 7, qualityScore: 1)
        ]
        let formatted = AudioFileImportController.formatTranscriptWithSpeakerAttribution(
            transcription: transcription, diarizationSegments: diarization, meetingStart: Date(timeIntervalSince1970: 0)
        )
        let attribution = try #require(formatted.attribution?.validated(for: formatted.transcript))
        #expect(attribution.speakers.count == 2)
        #expect(attribution.speakers.allSatisfy { $0.source == .unknown })
        let first = try #require(MeetingSpeakerRename.rename(speakerID: attribution.speakers[0].id,
            to: "Alex", in: formatted.transcript, attribution: attribution))
        let both = try #require(MeetingSpeakerRename.rename(speakerID: attribution.speakers[1].id,
            to: "Alex", in: first.transcript, attribution: first.attribution))
        let corrected = try #require(MeetingSpeakerRename.rename(speakerID: attribution.speakers[0].id,
            to: "Maria", in: both.transcript, attribution: both.attribution))
        #expect(corrected.transcript.contains("Maria: First decision."))
        #expect(corrected.transcript.contains("Alex: Second decision."))
        #expect(corrected.attribution.validated(for: corrected.transcript) != nil)
    }

    @Test("Unlabelled imported text does not fabricate speaker identity")
    func noInventedAttribution() {
        let transcription = SpeechTranscriptionResult(text: "Unlabelled speech.", segments: [])
        let formatted = AudioFileImportController.formatTranscriptWithSpeakerAttribution(
            transcription: transcription, diarizationSegments: [], meetingStart: Date()
        )
        #expect(formatted.transcript == "Unlabelled speech.")
        #expect(formatted.attribution == nil)
    }
}
