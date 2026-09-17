import FluidAudio
import Foundation
import GuesliCore

/// Native Swift transcription backend using FluidAudio's Parakeet TDT model
/// running on Apple's Neural Engine (ANE) via CoreML.
actor FluidAudioTranscriber {
    private var asrManager: AsrManager?
    private var loadGeneration: UInt64 = 0

    enum TranscriberError: Error, LocalizedError {
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "FluidAudio models not loaded. Call loadModels() first."
            }
        }
    }

    /// Downloads models (if needed) and initializes the ASR manager.
    func loadModels(
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        if asrManager != nil { return }
        let generation = loadGeneration

        fputs("[fluidaudio] downloading/loading Parakeet v3...\n", stderr)
        let plan = ManagedASRModelPlans.parakeetV3()
        let manager = try await ManagedASRModelDownloader.loadValidated(
            plan,
            progress: progress,
            progressSnapshot: progressSnapshot
        ) { modelDirectory in
            let preparing = ModelDownloadProgress.preparing(
                modelID: plan.modelID,
                message: "Loading Parakeet into Core ML..."
            )
            progress?(0.95, preparing.message)
            progressSnapshot?(preparing)
            let models = try await AsrModels.load(from: modelDirectory, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        guard generation == loadGeneration else { throw CancellationError() }
        self.asrManager = manager
        let preparing = ModelDownloadProgress.preparing(
            modelID: plan.modelID,
            message: "Loading Parakeet into Core ML..."
        )
        progress?(1, nil)
        progressSnapshot?(preparing.replacing(phase: .ready, message: "Model ready"))
        fputs("[fluidaudio] models ready\n", stderr)
    }

    /// Transcribe a WAV file URL directly.
    /// `language` is an optional ISO code enabling FluidAudio's script-level
    /// token filter on the v3 joint decoder (nil = auto).
    func transcribe(wavURL: URL, language: String? = nil) async throws -> ASRResult {
        guard let asrManager else { throw TranscriberError.notLoaded }
        let languageHint = language.flatMap(Language.init(rawValue:))
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        return try await asrManager.transcribe(wavURL, decoderState: &decoderState, language: languageHint)
    }

    func shutdown() {
        asrManager = nil
        loadGeneration &+= 1
    }
}
