import Foundation
import GuesliCore

extension MeetingProcessingConfiguration {
    static func snapshot(config: AppConfig, audioSources: [String] = []) -> Self {
        let backend = config.meetingSummaryBackend.isEmpty ? "chatgpt" : config.meetingSummaryBackend.lowercased()
        let model: String
        switch backend {
        case MeetingSummaryBackendOption.chatGPT.backend:
            model = MeetingSummaryClient.resolvedChatGPTModel(config.chatGPTModel)
        case MeetingSummaryBackendOption.openAI.backend:
            model = config.openAIModel.isEmpty ? AppConfig.defaultOpenAIModel : config.openAIModel
        case MeetingSummaryBackendOption.openRouter.backend:
            let configured = config.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
            model = configured.isEmpty ? MeetingSummaryClient.defaultOpenRouterModel : configured
        case MeetingSummaryBackendOption.ollama.backend:
            let configured = config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            model = configured.isEmpty ? MeetingSummaryClient.defaultOllamaModel : configured
        case MeetingSummaryBackendOption.lmStudio.backend:
            model = config.lmStudioModel.trimmingCharacters(in: .whitespacesAndNewlines)
        default: model = config.customLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = Self(asrBackend: config.meetingTranscriptionBackend, asrModel: config.meetingTranscriptionModel,
                    summaryBackend: backend, summaryModel: model, audioSources: audioSources)
        result.summaryRetryCount = config.meetingSummaryRetryCount
        return result
    }
}
