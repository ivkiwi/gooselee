import Foundation
import Testing
@testable import GuesliApp

@Suite("Dictation cleanup safety", .guesliHermeticSupport)
struct DictationCleanupSafetyTests {
    @Test("Local context must fit the full prompt and expected reply")
    func contextBudget() {
        #expect(DictationCleanupSafety.hasContextBudget(promptTokens: 650, replyTokens: 350, contextTokens: 1024))
        #expect(!DictationCleanupSafety.hasContextBudget(promptTokens: 1024, replyTokens: 0, contextTokens: 1024))
        #expect(!DictationCleanupSafety.hasContextBudget(promptTokens: 512, replyTokens: 512, contextTokens: 1024))
        #expect(!DictationCleanupSafety.hasContextBudget(promptTokens: Int.max, replyTokens: 1, contextTokens: 1024))
    }

    @Test("Placeholder ellipses cannot replace a real transcript")
    func ellipsisPlaceholder() {
        for output in ["...", "…", " . . . "] {
            #expect(Qwen3PostProcessorOutputCleaner.shouldFallbackToInput(cleaned: output, input: "Полная исходная расшифровка"))
        }
        #expect(!Qwen3PostProcessorOutputCleaner.shouldFallbackToInput(cleaned: "Подождём…", input: "подождём"))
    }

    @Test("Any truncated completion choice rejects the cleanup response")
    func truncatedExternalResponse() {
        let complete: [String: Any] = ["message": ["content": "Полный текст."], "finish_reason": "stop"]
        let incomplete: [String: Any] = ["message": ["content": "Начало правдоподобного ответа"], "finish_reason": "length"]
        for choices in [[incomplete], [complete, incomplete]] {
            #expect(throws: DictationCleanupError.self) {
                try DictationCleanupSafety.requireCompletedResponse(["choices": choices])
            }
        }
    }

    @Test("Complete and legacy cleanup payloads remain accepted")
    func completedExternalResponse() throws {
        try DictationCleanupSafety.requireCompletedResponse(["choices": [["finish_reason": "stop"]]])
        try DictationCleanupSafety.requireCompletedResponse(["choices": [["message": ["content": "Готово."]]]])
    }

    @Test("Rejected external cleanup keeps the ASR result for the normal fallback")
    func rejectedCleanupRetainsRawTranscript() async throws {
        let coordinator = TranscriptionCoordinator(externalTranscriptCleanup: { _, _, _ in
            try DictationCleanupSafety.requireCompletedResponse(["choices": [["finish_reason": "length"]]])
            return "Обрезанный ответ"
        })
        await coordinator.setTranscriptCleanupSettings(TranscriptCleanupSettings(provider: .openAI))
        let original = SpeechTranscriptionResult(text: "Полная исходная расшифровка.", segments: [])
        let cleaned = await coordinator.postProcessDictationIfNeeded(original, backend: .gigaAMV3Russian, enabled: true)
        #expect(cleaned == nil)
    }
}
