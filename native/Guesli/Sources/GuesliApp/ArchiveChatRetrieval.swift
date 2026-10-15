import Foundation
import GuesliCore

struct ArchiveChatScope: Equatable, Sendable {
    var meetingID: Int64? = nil
    var folderID: Int64? = nil
    var fromDate: Date? = nil
    var toDate: Date? = nil

    static let all = ArchiveChatScope()
    static func meeting(_ id: Int64) -> Self { Self(meetingID: id) }
    static func folder(_ id: Int64) -> Self { Self(folderID: id) }
}

enum ArchiveChatSourceKind: String, Codable, Sendable {
    case transcript, summary, manualNotes

    var label: String {
        switch self {
        case .transcript: return String(localized: "Transcript")
        case .summary: return String(localized: "Summary")
        case .manualNotes: return String(localized: "Manual notes")
        }
    }

    func text(in meeting: MeetingRecord) -> String {
        switch self {
        case .transcript: return meeting.rawTranscript
        case .summary: return meeting.formattedNotes
        case .manualNotes: return meeting.manualNotes
        }
    }

    func version(in meeting: MeetingRecord) -> Int64 {
        switch self {
        case .transcript: return meeting.transcriptRevision
        case .summary: return meeting.summaryRevision
        case .manualNotes: return meeting.contentRevision
        }
    }
}

struct ArchiveChatSource: Identifiable, Equatable, Sendable {
    let id: String
    let meetingID: Int64
    let kind: ArchiveChatSourceKind
    let contentVersion: Int64
    let range: NSRange
    let text: String
    let title: String
    let date: String
    let staleSummary: Bool

    enum Availability: Equatable { case current, stale, unavailable }

    func availability(in meeting: MeetingRecord?) -> Availability {
        guard let meeting, meeting.id == meetingID else { return .unavailable }
        let full = kind.text(in: meeting) as NSString
        guard kind.version(in: meeting) == contentVersion,
              range.location >= 0, range.length > 0,
              range.location <= full.length, range.length <= full.length - range.location,
              full.substring(with: range) == text else { return .stale }
        if kind == .summary, meeting.summaryIsStale != staleSummary { return .stale }
        return .current
    }
}

struct ArchiveChatRetrieval {
    let sources: [ArchiveChatSource]
    let limited: Bool

    // Literal significant words only; no morphology or semantic-search claim.
    static func terms(in question: String) -> [String] {
        let stop: Set<String> = [
            "it", "is", "to", "of", "on", "in", "an", "as", "at", "by", "we", "he", "be", "do", "or", "me", "my", "us", "no",
            "the", "and", "for", "with", "that", "this", "from", "what", "when", "where", "who", "how", "was", "were", "are", "does", "did", "about", "have", "has", "can", "you", "our", "its", "owns", "owner", "responsible",
            "по", "на", "не", "за", "со", "из", "до", "об", "от", "во", "же", "ли", "ты", "мы", "он", "ее", "её", "их", "вы", "то", "та", "те", "ну", "да", "но", "бы",
            "что", "как", "кто", "где", "когда", "это", "этот", "этой", "того", "для", "или", "был", "была", "были", "есть", "про", "при", "нам", "нас", "мне", "его", "она", "они", "оно", "какой", "какие", "какая", "встречах", "встречи", "ответственный"
        ]
        var seen: Set<String> = []
        return question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 2 && !stop.contains($0) && seen.insert($0).inserted }
            .prefix(12).map { $0 }
    }

    static func retrieve(meetings: [MeetingRecord], terms: [String], excluded: Set<Int64>, characterBudget: Int) -> Self {
        let candidates = meetings.filter { !excluded.contains($0.id) }.prefix(20)
        struct Piece { let meeting: MeetingRecord; let kind: ArchiveChatSourceKind; let range: NSRange; let text: String; let score: Int }
        var pieces: [Piece] = []
        for meeting in candidates {
            let hasOriginal = !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            for kind in [ArchiveChatSourceKind.transcript, .manualNotes, .summary] {
                if kind == .summary && meeting.summaryIsStale && hasOriginal { continue }
                let text = kind.text(in: meeting)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let ns = text as NSString
                // At most two windows per text. Keep exact UTF-16 anchors into the stored version.
                var offsets = terms.compactMap { term -> Int? in
                    let match = ns.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
                    return match.location == NSNotFound ? nil : max(0, match.location - 300)
                }
                if offsets.isEmpty { offsets = [0] }
                var used: [NSRange] = []
                for offset in offsets.sorted() {
                    let raw = NSRange(location: offset, length: min(1_800, ns.length - offset))
                    let range = ns.rangeOfComposedCharacterSequences(for: raw)
                    guard !used.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
                    let snippet = ns.substring(with: range)
                    let score = terms.filter { snippet.localizedCaseInsensitiveContains($0) }.count * 10
                        + (kind == .transcript ? 3 : kind == .manualNotes ? 2 : 0)
                    pieces.append(Piece(meeting: meeting, kind: kind, range: range, text: snippet, score: score))
                    used.append(range)
                    if used.count == 2 { break }
                }
            }
        }
        pieces.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.meeting.startTime != $1.meeting.startTime { return $0.meeting.startTime > $1.meeting.startTime }
            if $0.meeting.id != $1.meeting.id { return $0.meeting.id < $1.meeting.id }
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.range.location < $1.range.location
        }
        var budget = max(0, characterBudget)
        var sources: [ArchiveChatSource] = []
        var clipped = false
        for piece in pieces {
            // Reserve title/date/JSON overhead as well as the source text itself.
            let overhead = min(piece.meeting.title.count, 200) + 300
            guard sources.count < 12, budget > overhead + 100 else { break }
            let text = String(piece.text.prefix(min(2_000, budget - overhead)))
            clipped = clipped || text.count < piece.text.count
            let range = NSRange(location: piece.range.location, length: (text as NSString).length)
            sources.append(ArchiveChatSource(
                id: "S\(sources.count + 1)", meetingID: piece.meeting.id, kind: piece.kind,
                contentVersion: piece.kind.version(in: piece.meeting), range: range, text: text,
                title: String(piece.meeting.title.prefix(200)), date: piece.meeting.startTime,
                staleSummary: piece.kind == .summary && piece.meeting.summaryIsStale
            ))
            budget -= text.count + overhead
        }
        return Self(sources: sources, limited: clipped || meetings.count > 20 || pieces.count > sources.count)
    }

    static func invalidCitations(in answer: String, sources: [ArchiveChatSource]) -> [String] {
        let issued = Set(sources.map(\.id))
        let regex = try! NSRegularExpression(pattern: #"\[([^\]\n]{1,80})\]"#)
        let ns = answer as NSString
        let cited = regex.matches(in: answer, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
        var invalid = Set(cited.filter { !issued.contains($0) })
        if !cited.contains(where: { issued.contains($0) }) { invalid.insert("missing citations") }
        return invalid.sorted()
    }
}
