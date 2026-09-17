import Testing
@testable import GuesliApp

@Suite("Supported ASR backends", .guesliHermeticSupport)
struct SupportedASRBackendTests {
    @Test("catalog contains exactly the three primary ASR models")
    func focusedCatalog() {
        #expect(BackendOption.all == [
            .gigaAMV3Russian,
            .parakeetMultilingual,
            .nemotron35Multilingual,
        ])
    }

    @Test("Parakeet uses the multilingual v3 FluidInference model")
    func parakeetV3() {
        #expect(BackendOption.parakeetMultilingual.backend == "fluidaudio")
        #expect(BackendOption.parakeetMultilingual.model.contains("FluidInference"))
        #expect(BackendOption.parakeetMultilingual.model.contains("v3"))
    }

    @Test("only Nemotron is excluded from recorded meeting transcription")
    func meetingEligibility() {
        #expect(BackendOption.gigaAMV3Russian.supportsMeetingTranscription)
        #expect(BackendOption.parakeetMultilingual.supportsMeetingTranscription)
        #expect(!BackendOption.nemotron35Multilingual.supportsMeetingTranscription)
    }

    @Test("catalog metadata remains user readable")
    func metadata() {
        for option in BackendOption.all {
            #expect(option.sizeLabel.contains("MB") || option.sizeLabel.contains("GB"))
            #expect(option.description.count > 20)
        }
    }
}
