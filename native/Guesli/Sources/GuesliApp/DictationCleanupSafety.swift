import Foundation

enum DictationCleanupSafety {
    static func hasContextBudget(promptTokens: Int, replyTokens: Int, contextTokens: Int) -> Bool {
        promptTokens >= 0 && replyTokens >= 0 && promptTokens < contextTokens
            && replyTokens < contextTokens - promptTokens
    }

    static func requireCompletedResponse(_ payload: [String: Any]) throws {
        let choices = payload["choices"] as? [[String: Any]] ?? []
        if MeetingSummaryClient.incompleteResponseReason(from: payload) != nil
            || choices.contains(where: { MeetingSummaryClient.incompleteResponseReason(from: ["choices": [$0]]) != nil }) {
            throw DictationCleanupError.incompleteResponse
        }
    }
}

enum DictationCleanupError: LocalizedError {
    case contextExceeded
    case incompleteResponse

    var errorDescription: String? {
        switch self {
        case .contextExceeded:
            return String(localized: "Dictation exceeds the local cleanup context. Keeping the original text.")
        case .incompleteResponse:
            return String(localized: "Text cleanup returned an incomplete response. Keeping the original text.")
        }
    }
}
