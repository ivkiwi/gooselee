import Testing
@testable import GuesliCore
@testable import GuesliApp

@Suite("Managed ASR model lifecycle")
struct ManagedASRModelLifecycleTests {
    @Test("supported managed plans are Parakeet v3 and optional English EOU")
    func supportedManagedPlans() {
        #expect(ManagedASRModelPlans.parakeetV3().modelID == BackendOption.parakeetMultilingual.model)
        #expect(ManagedASRModelPlans.parakeetRealtimeEOU320().modelID.contains("parakeet-realtime-eou"))
    }

    @Test("streaming dictation backend is not meeting eligible")
    func meetingEligibilityExcludesStreamingBackend() {
        #expect(!BackendOption.nemotron35Multilingual.supportsMeetingTranscription)
        #expect(BackendOption.gigaAMV3Russian.supportsMeetingTranscription)
        #expect(BackendOption.parakeetMultilingual.supportsMeetingTranscription)
    }
}
