import Foundation

struct MeetingPreparationNotification: Equatable {
    let title: String
    let body: String

    static func make(title: String, notes: String, maxBodyLength: Int = 480) -> Self? {
        guard maxBodyLength > 0 else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sections = PreviousMeetingNotes.extract(from: trimmed)
        var parts: [String] = []
        let availableSections = [sections.actions, sections.decisions].filter { !$0.isEmpty }.count
        let sectionLimit = max(1, (maxBodyLength - 24) / max(availableSections, 1))
        if !sections.actions.isEmpty {
            parts.append(String(localized: "Tasks:") + "\n" + shortened(plainText(sections.actions), to: sectionLimit))
        }
        if !sections.decisions.isEmpty {
            parts.append(String(localized: "Decisions:") + "\n" + shortened(plainText(sections.decisions), to: sectionLimit))
        }
        let body = parts.isEmpty ? plainText(trimmed) : parts.joined(separator: "\n\n")
        return Self(title: String(localized: "Before meeting: \(title)"), body: shortened(body, to: maxBodyLength))
    }

    private static func shortened(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(max(0, limit - 1))) + "…" : text
    }

    private static func plainText(_ markdown: String) -> String {
        markdown.components(separatedBy: .newlines).map { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            for marker in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "] {
                if text.hasPrefix(marker) { text = "- " + String(text.dropFirst(marker.count)); break }
            }
            if text.hasPrefix("#") { text = text.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        }.joined(separator: "\n")
    }
}
