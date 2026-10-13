import Foundation

struct PreviousMeetingNotes: Equatable {
    let decisions: String
    let actions: String

    var isEmpty: Bool { decisions.isEmpty && actions.isEmpty }

    static func extract(from markdown: String) -> PreviousMeetingNotes {
        var decisions: [String] = []
        var actions: [String] = []
        var section: Section?
        var sectionLevel = 0
        var fence: Character?

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            if isFence {
                let marker = trimmed.first!
                if fence == marker { fence = nil }
                else if fence == nil { fence = marker }
            }
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if fence == nil, !isFence, (1...6).contains(level), trimmed.dropFirst(level).first?.isWhitespace == true {
                let heading = trimmed.dropFirst(level)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#*: "))
                    .lowercased()
                if let matched = Section(heading: heading) {
                    section = matched
                    sectionLevel = level
                    continue
                }
                if level <= sectionLevel { section = nil }
            }
            switch section {
            case .decisions: decisions.append(line)
            case .actions: actions.append(line)
            case nil: break
            }
        }
        return PreviousMeetingNotes(
            decisions: decisions.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            actions: actions.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private enum Section {
        case decisions, actions

        init?(heading: String) {
            switch heading {
            case "решения", "decisions", "decision and next steps", "решение и следующие шаги",
                 "coordination notes", "координация", "заметки по координации":
                self = .decisions
            case "todo / исправления / доделки", "todo / fixes / follow-ups", "todo / fixes / finishing touches",
                 "todo / fixes / improvements", "todo", "действия", "actions", "action items", "задачи",
                 "commitments", "обязательства", "договорённости", "договоренности", "next steps", "следующие шаги",
                 "today", "сегодня":
                self = .actions
            default:
                // The automatic template translates the TODO heading to the meeting language.
                guard heading.hasPrefix("todo /") else { return nil }
                self = .actions
            }
        }
    }
}
