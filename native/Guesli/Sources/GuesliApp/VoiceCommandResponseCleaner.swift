import Foundation

enum VoiceCommandResponseCleaner {
    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"(?is)<think\b[^>]*>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<think\b[^>]*>.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(
            of: #"(?i)^(?:(?:конечно|готово|sure)[.!,:]?\s*)?(?:вот\s+(?:(?:исправленный|улучшенный|отредактированный|готовый)\s+)?(?:текст|вариант|ответ|результат)|(?:исправленный|улучшенный|отредактированный|готовый)\s+(?:текст|вариант|ответ)|результат|here(?:['’]s| is)\s+(?:(?:the|your)\s+)?(?:(?:revised|rewritten|edited|improved)\s+)?(?:text|reply|draft|email))\s*:\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"),
           let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...].dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("«", "»"), ("“", "”")]
        for (opening, closing) in quotePairs {
            if text.count >= 2, text.first == opening, text.last == closing {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    static func validated(_ raw: String) throws -> String {
        let text = clean(raw)
        // LLM.swift reports an overflowed or empty local generation as "...".
        guard !text.isEmpty, text != "..." else { throw VoiceCommandError.emptyResponse }
        return text
    }
}
