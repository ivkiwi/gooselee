import Testing
@testable import GuesliApp
import GuesliCore

@Suite("Processing provider snapshots", .guesliHermeticSupport)
struct MeetingProcessingSnapshotTests {
    @Test("History records the same normalized model as the provider transport")
    func selectedModelMatchesTransport() {
        var config = AppConfig()
        config.meetingSummaryBackend = "openrouter"
        config.openRouterModel = "  selected-model \n"
        #expect(MeetingProcessingConfiguration.snapshot(config: config).summaryModel == "selected-model")
        config.openRouterModel = " \n"
        #expect(MeetingProcessingConfiguration.snapshot(config: config).summaryModel == MeetingSummaryClient.defaultOpenRouterModel)
        config.meetingSummaryBackend = "ollama"
        config.ollamaModel = " local-model "
        #expect(MeetingProcessingConfiguration.snapshot(config: config).summaryModel == "local-model")
        config.ollamaModel = ""
        #expect(MeetingProcessingConfiguration.snapshot(config: config).summaryModel == MeetingSummaryClient.defaultOllamaModel)
        config.meetingSummaryBackend = "lmstudio"
        config.lmStudioModel = " studio-model "
        #expect(MeetingProcessingConfiguration.snapshot(config: config).summaryModel == "studio-model")
    }
}
