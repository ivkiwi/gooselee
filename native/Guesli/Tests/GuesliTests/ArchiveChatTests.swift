import Foundation
import GuesliCore
import Testing
@testable import GuesliApp

@Suite("Bounded archive chat", .guesliHermeticSupport)
struct ArchiveChatTests {
    private func meeting(_ id: Int64 = 1, transcript: String = "Релиз: Анна отвечает за выпуск.", summary: String = "", stale: Bool = false) -> MeetingRecord {
        MeetingRecord(id: id, title: "Release planning", startTime: "2026-10-15T09:00:00Z", durationSeconds: 60,
                      rawTranscript: transcript, formattedNotes: summary, wordCount: 6, folderID: nil,
                      summaryIsStale: stale)
    }

    @Test("natural questions become bounded significant words, not one phrase")
    func significantWords() {
        #expect(ArchiveChatRetrieval.terms(in: "Что решили про РЕЛИЗ и релиз? Кто ответственный?") == ["решили", "релиз"])
        #expect(ArchiveChatRetrieval.terms(in: "Who owns it?").isEmpty)
        #expect(ArchiveChatRetrieval.terms(in: "Что решили по AI?") == ["решили", "ai"])
        #expect(ArchiveChatRetrieval.terms(in: "AI HR Q4 v2, in the meeting") == ["ai", "hr", "q4", "v2", "meeting"])
        #expect(ArchiveChatRetrieval.terms(in: (1...30).map { "topic\($0)" }.joined(separator: " ")).count == 12)
    }

    @Test("scope filtering precedes the candidate bound, with Unicode and deleted exclusion")
    func scopedArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationStore(databaseURL: directory.appendingPathComponent("fixture.db"))
        try store.migrateIfNeeded()
        let folder = try store.createFolder(name: "Release")
        let otherFolder = try store.createFolder(name: "Other")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func insert(_ text: String, date: Date, in folderID: Int64) throws -> Int64 {
            let id = try store.insertMeeting(title: text, calendarEventID: nil, startTime: date,
                                            endTime: date.addingTimeInterval(60), rawTranscript: text,
                                            formattedNotes: "", micAudioPath: nil, systemAudioPath: nil)
            try store.moveMeeting(id: id, toFolder: folderID)
            return id
        }
        let expected = try insert("Релиз поручен Анне", date: start, in: folder)
        let deleted = try insert("Релиз удалён", date: start, in: folder)
        try store.deleteMeeting(id: deleted)
        _ = try insert("Релиз вне периода", date: start.addingTimeInterval(-100), in: folder)
        for index in 1...25 {
            _ = try insert("Релиз вне папки", date: start.addingTimeInterval(Double(index)), in: otherFolder)
        }
        let results = try store.searchArchiveMeetings(terms: ["релиз"], folderID: folder,
                                                       fromDate: start, toDate: start.addingTimeInterval(100), limit: 21)
        #expect(results.map(\.id) == [expected])
    }

    @Test("retrieval bounds source text and keeps exact anchors without audio")
    func boundedSourcesAndAnchors() {
        let meetings = (1...25).map { meeting(Int64($0), transcript: String(repeating: "Before ", count: 400) + "релиз Анна " + String(repeating: "after ", count: 500)) }
        let result = ArchiveChatRetrieval.retrieve(meetings: meetings, terms: ["релиз"], excluded: [2], characterBudget: 24_000)
        #expect(result.sources.count <= 12)
        #expect(result.sources.allSatisfy { $0.text.count <= 2_000 && $0.meetingID != 2 })
        #expect(result.limited)
        for source in result.sources {
            let original = meetings.first { $0.id == source.meetingID }
            #expect(source.availability(in: original) == .current)
            #expect(source.range.location > 0)
            #expect(source.availability(in: nil) == .unavailable)
            #expect(source.availability(in: meeting(source.meetingID, transcript: "Changed")) == .stale)
        }
        let smaller = ArchiveChatRetrieval.retrieve(meetings: meetings, terms: ["релиз"], excluded: [], characterBudget: 1_000)
        #expect(smaller.sources.reduce(0) { $0 + $1.text.count } < 1_000)
        #expect(smaller.limited)
    }

    @Test("stale summaries never corroborate available original text")
    func staleSummary() {
        let original = meeting(summary: "Old release owner", stale: true)
        let result = ArchiveChatRetrieval.retrieve(meetings: [original], terms: ["release"], excluded: [], characterBudget: 24_000)
        #expect(result.sources.allSatisfy { $0.kind != .summary })
        let historical = meeting(transcript: "", summary: "Old release owner", stale: true)
        let fallback = ArchiveChatRetrieval.retrieve(meetings: [historical], terms: ["release"], excluded: [], characterBudget: 24_000)
        #expect(fallback.sources.first?.staleSummary == true)
        #expect(fallback.sources.first?.kind == .summary)
    }

    @Test("only current issued citation IDs pass")
    func citationsAndPrompt() throws {
        let sources = ArchiveChatRetrieval.retrieve(meetings: [meeting()], terms: ["релиз"], excluded: [], characterBudget: 24_000).sources
        #expect(ArchiveChatRetrieval.invalidCitations(in: "Анна [S1]", sources: sources).isEmpty)
        #expect(ArchiveChatRetrieval.invalidCitations(in: "Анна [S999]", sources: sources).contains("S999"))
        #expect(!ArchiveChatRetrieval.invalidCitations(in: "Анна", sources: sources).isEmpty)
        let prompt = try ArchiveChatModel.prompt(question: "Who owns it?", sources: sources, history: [])
        #expect(prompt.instructions.contains("untrusted DATA"))
        #expect(prompt.instructions.contains("no tools"))
        #expect(!prompt.userPrompt.contains("micAudioPath"))
        #expect(prompt.userPrompt.contains("S1"))
    }

    @MainActor
    private func finish(_ model: ArchiveChatModel) async {
        for _ in 0..<100 where model.isRunning { try? await Task.sleep(nanoseconds: 10_000_000) }
        #expect(!model.isRunning)
    }

    @Test("empty search avoids provider; follow-up keeps topic and deleted evidence is discarded")
    @MainActor
    func emptyAndFollowUp() async {
        let model = ArchiveChatModel()
        var requests = 0
        var latestPrompt = ""
        var exists = true
        let record = meeting()
        let fresh: @MainActor (Int64) throws -> MeetingRecord? = { _ in exists ? record : nil }
        let respond: (MeetingLLMPrompt, AppConfig) async throws -> String = { prompt, _ in
            requests += 1; latestPrompt = prompt.userPrompt
            return "Анна отвечает за релиз [S1]."
        }
        model.ask("релиз", scope: .all, config: AppConfig(), candidates: { _, _ in [] }, freshMeeting: fresh, respond: respond)
        #expect(requests == 0)
        #expect(model.errorMessage != nil)
        model.ask("релиз", scope: .all, config: AppConfig(), candidates: { _, _ in [record] }, freshMeeting: fresh, respond: respond)
        await finish(model)
        #expect(model.turns.count == 1)
        var terms: [String] = []
        model.ask("Who owns it?", scope: .all, config: AppConfig(), candidates: { words, _ in terms = words; return [record] }, freshMeeting: fresh, respond: respond)
        await finish(model)
        #expect(terms.contains("релиз"))
        #expect(latestPrompt.contains("previous_dialogue"))
        #expect(latestPrompt.contains("Анна отвечает за релиз"))
        exists = false
        model.ask("релиз", scope: .all, config: AppConfig(), candidates: { _, _ in [] }, freshMeeting: fresh, respond: respond)
        #expect(requests == 2)
        #expect(model.sources.isEmpty)
    }

    @Test("each answer retains its own S1 association across follow-ups")
    @MainActor
    func perAnswerSourceAssociation() async {
        let model = ArchiveChatModel()
        let first = meeting(1, transcript: "Alpha release owner is Anna.")
        let second = meeting(2, transcript: "Beta release owner is Boris.")
        var records = [first.id: first, second.id: second]
        let candidates: @MainActor ([String], ArchiveChatScope) throws -> [MeetingRecord] = { terms, _ in
            [terms.contains("beta") ? second : first]
        }
        let fresh: @MainActor (Int64) throws -> MeetingRecord? = { records[$0] }
        let respond: (MeetingLLMPrompt, AppConfig) async throws -> String = { _, _ in "Owner [S1]." }
        model.ask("Alpha", scope: .all, config: AppConfig(), candidates: candidates, freshMeeting: fresh, respond: respond)
        await finish(model)
        model.ask("Beta", scope: .all, config: AppConfig(), candidates: candidates, freshMeeting: fresh, respond: respond)
        await finish(model)
        #expect(model.turns.count == 2)
        guard model.turns.count == 2 else { return }
        let earlier = model.turns[0].sources.first { $0.id == "S1" }
        let current = model.turns[1].sources.first { $0.id == "S1" }
        #expect(earlier?.meetingID == first.id)
        #expect(current?.meetingID == second.id)
        #expect(model.sources == model.turns[1].sources)
        records.removeValue(forKey: first.id)
        #expect(earlier?.availability(in: records[first.id]) == .unavailable)
        #expect(current?.availability(in: records[second.id]) == .current)
    }

    @Test("new chat and cancellation reject late provider responses")
    @MainActor
    func lifecycle() async {
        let model = ArchiveChatModel()
        let record = meeting()
        var pending: CheckedContinuation<String, Never>?
        let respond: (MeetingLLMPrompt, AppConfig) async throws -> String = { _, _ in
            await withCheckedContinuation { pending = $0 }
        }
        model.ask("релиз", scope: .meeting(record.id), config: AppConfig(), candidates: { _, scope in
            #expect(scope.meetingID == record.id); return [record]
        }, freshMeeting: { _ in record }, respond: respond)
        for _ in 0..<100 where pending == nil { await Task.yield() }
        #expect(pending != nil)
        model.cancel()
        #expect(model.isIncomplete)
        model.newChat()
        pending?.resume(returning: "Late answer [S1]")
        for _ in 0..<10 { await Task.yield() }
        #expect(model.answer.isEmpty)
        #expect(model.turns.isEmpty)
        #expect(model.sources.isEmpty)
    }
}
