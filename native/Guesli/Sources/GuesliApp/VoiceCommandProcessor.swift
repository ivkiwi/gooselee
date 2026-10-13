import Foundation

enum VoiceCommandProcessor {
    static func failureMessage(_ error: Error) -> String {
        let reason = (error as? VoiceCommandError)?.errorDescription
            ?? String(localized: "Check your text processing model or account and try again.")
        return reason + "\n\n" + String(localized: "Your instruction is in the clipboard.")
    }

    static func process(
        instruction: String,
        context: DictationContext?,
        config: AppConfig,
        coordinator: TranscriptionCoordinator
    ) async throws -> String {
        var settings = TranscriptCleanupSettings(config: config)
        let prompt = try VoiceCommandPrompt.user(
            instruction: instruction,
            context: context,
            includeScreenContext: config.enableScreenContext,
            maxScreenContextCharacters: settings.provider == .local ? VoiceCommandPrompt.localScreenContextCharacters : nil
        )
        settings.systemPrompt = VoiceCommandPrompt.system
        if settings.provider == .local {
            return try await coordinator.generateVoiceCommand(prompt)
        }
        return try await ExternalTranscriptCleanupClient.cleanup(
            prompt,
            appContext: nil,
            settings: settings,
            isVoiceCommand: true
        )
    }
}
