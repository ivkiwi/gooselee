import Foundation

/// Display-only attribution for one ASR generation. It contains no bridge events or contacts.
public struct MeetingSpeakerAttribution: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case user
        case googleMeet
        case unknown
    }

    public struct Speaker: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public var displayName: String
        public var source: Source

        public init(id: String, displayName: String, source: Source) {
            self.id = id
            self.displayName = displayName
            self.source = source
        }
    }

    public let generationID: String
    public var speakers: [Speaker]
    /// One entry per physical transcript line, including blank lines.
    public let lineSpeakerIDs: [String?]

    public init(generationID: String, speakers: [Speaker], lineSpeakerIDs: [String?]) {
        self.generationID = generationID
        self.speakers = speakers
        self.lineSpeakerIDs = lineSpeakerIDs
    }

    public var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ json: String?) -> Self? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func speaker(atLine index: Int) -> Speaker? {
        guard lineSpeakerIDs.indices.contains(index), let id = lineSpeakerIDs[index] else { return nil }
        return speakers.first { $0.id == id }
    }

    /// Reject shifted annotations instead of silently renaming another person's words.
    public func validated(for transcript: String) -> Self? {
        let lines = transcript.components(separatedBy: "\n")
        guard lines.count == lineSpeakerIDs.count,
              Set(speakers.map(\.id)).count == speakers.count else { return nil }
        for (index, line) in lines.enumerated() {
            guard let id = lineSpeakerIDs[index] else { continue }
            guard let speaker = speakers.first(where: { $0.id == id }),
                  Self.lineHeader(line)?.label == speaker.displayName else { return nil }
        }
        return self
    }

    /// Legacy labels cannot recover distinct people whose names were already projected alike.
    public static func legacy(transcript: String) -> Self {
        let generation = "legacy"
        var speakers: [Speaker] = []
        let ids = transcript.components(separatedBy: "\n").map { line -> String? in
            guard let label = lineHeader(line)?.label else { return nil }
            if let speaker = speakers.first(where: { $0.displayName == label }) { return speaker.id }
            let id = generation + ":" + String(speakers.count) + ":" + label
            speakers.append(Speaker(id: id, displayName: label, source: .unknown))
            return id
        }
        return Self(generationID: generation, speakers: speakers, lineSpeakerIDs: ids)
    }

    public static func lineHeader(_ line: String) -> (prefix: String, label: String, suffix: String)? {
        guard let labelStart = line.range(of: #"^\[\d{2}:\d{2}:\d{2}\] "#, options: .regularExpression)?.upperBound,
              let colon = line[labelStart...].firstIndex(of: ":"), colon > labelStart else { return nil }
        return (String(line[..<labelStart]), String(line[labelStart..<colon]), String(line[colon...]))
    }

    /// Cleanup may edit words and blank lines, but cannot reassign or merge speaker turns.
    public func rebased(from original: String, to cleaned: String) -> Self? {
        guard validated(for: original) != nil else { return nil }
        let before = original.components(separatedBy: "\n").enumerated().compactMap { index, line in
            Self.lineHeader(line).map { (header: $0, id: lineSpeakerIDs[index]) }
        }
        var cursor = 0
        var ids: [String?] = []
        for line in cleaned.components(separatedBy: "\n") {
            guard let header = Self.lineHeader(line) else {
                ids.append(nil)
                continue
            }
            guard cursor < before.count,
                  before[cursor].header.prefix == header.prefix,
                  before[cursor].header.label == header.label else { return nil }
            ids.append(before[cursor].id)
            cursor += 1
        }
        guard cursor == before.count else { return nil }
        return Self(generationID: generationID, speakers: speakers, lineSpeakerIDs: ids)
    }
}
