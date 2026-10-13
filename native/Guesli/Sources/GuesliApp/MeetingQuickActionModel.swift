import Foundation
import GuesliCore
import Observation

extension MeetingSummaryClient {
    static func quickAction(
        _ action: MeetingQuickAction,
        transcript: String,
        meetingTitle: String,
        config: AppConfig
    ) async throws -> String {
        let data = try MeetingQuickAction.conversationData(transcript: transcript, meetingTitle: meetingTitle)
        let template = MeetingTemplateSnapshot(
            id: "quick-action-\(action.rawValue)", name: action.title, kind: .auto, prompt: action.instructions
        )
        return try await withSummaryTimeout(seconds: usesLocalSummaryRetryPolicy(config: config) ? 180 : 90) {
            try await summarizeOnce(
                transcript: data, meetingTitle: action.title, config: config, template: template,
                existingNotes: nil, manualNotesToRetain: nil, visualContext: nil
            )
        }
    }
}

@MainActor
@Observable
final class MeetingQuickActionModel {
    private(set) var meetingID: Int64?
    private(set) var action: MeetingQuickAction?
    private(set) var answer = ""
    private(set) var errorMessage: String?
    private(set) var isRunning = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var meetingRecordProvider: (@MainActor (Int64) -> MeetingRecord?)?

    func run(
        _ action: MeetingQuickAction,
        meetingID: Int64,
        transcript: String,
        meetingTitle: String,
        config: AppConfig,
        isChatGPTAuthenticated: Bool,
        isCurrentMeeting: @escaping @MainActor () -> Bool
    ) {
        guard !isRunning else { return }
        reset()
        self.meetingID = meetingID
        self.action = action
        if let hint = Self.configurationHint(config: config, isChatGPTAuthenticated: isChatGPTAuthenticated) {
            errorMessage = hint
            return
        }
        // Transcript timestamps follow recorded audio, which stops during pauses, so the window
        // ends at the latest line rather than at the wall clock.
        let context = action == .catchUp
            ? MeetingQuickActionTranscript.lastMinutes(2, from: transcript)
            : transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            errorMessage = action == .catchUp
                ? String(localized: "No timestamped transcript in the last two minutes. Try again when more speech is transcribed.")
                : String(localized: "No transcript to analyze yet. Wait for the meeting transcript.")
            return
        }
        isRunning = true
        let requestGeneration = generation
        task = Task { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try await MeetingSummaryClient.quickAction(
                    action, transcript: context, meetingTitle: meetingTitle, config: config
                ))
            } catch {
                result = .failure(error)
            }
            guard let self,
                  self.meetingID == meetingID, self.generation == requestGeneration else { return }
            guard isCurrentMeeting() else {
                self.reset()
                return
            }
            self.isRunning = false
            self.task = nil
            switch result {
            case .success(let answer):
                self.answer = answer
            case .failure(let error):
                self.errorMessage = Self.failureMessage(error)
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    func reset(for meetingID: Int64? = nil) {
        if let meetingID, self.meetingID != meetingID { return }
        cancel()
        self.meetingID = nil
        action = nil
        answer = ""
        errorMessage = nil
    }

    private static func configurationHint(config: AppConfig, isChatGPTAuthenticated: Bool) -> String? {
        let backend = config.meetingSummaryBackend.isEmpty ? "chatgpt" : config.meetingSummaryBackend.lowercased()
        let configured: Bool
        switch backend {
        case MeetingSummaryBackendOption.chatGPT.backend:
            configured = isChatGPTAuthenticated
        case MeetingSummaryBackendOption.openAI.backend:
            configured = !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? config.openAIAPIKey).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case MeetingSummaryBackendOption.openRouter.backend:
            configured = !(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? config.openRouterAPIKey).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case MeetingSummaryBackendOption.ollama.backend:
            configured = true
        case MeetingSummaryBackendOption.lmStudio.backend:
            configured = MeetingSummaryClient.lmStudioHasRequiredSettings(config: config)
        case MeetingSummaryBackendOption.customLLM.backend:
            configured = MeetingSummaryClient.customLLMHasRequiredSettings(config: config)
        default:
            configured = false
        }
        return configured ? nil : String(localized: "Set up AI in Settings → Meetings → Summary backend. Sign in to ChatGPT or configure the selected model, URL and API key.")
    }

    private static func failureMessage(_ error: Error) -> String {
        if let summaryError = error as? MeetingSummaryError {
            switch summaryError {
            case .requestFailed(_, let underlying):
                return failureMessage(underlying)
            case .emptyResponse:
                return String(localized: "AI returned an empty answer. Try again or check the model in meeting settings.")
            case .incompleteResponse:
                return String(localized: "AI did not finish the answer. Try again or choose another model in meeting settings.")
            case .backendFailed(_, let status, _):
                if status == 401 || status == 403 {
                    return String(localized: "AI access denied. Check your sign-in or API key in Settings → Meetings → Summary backend.")
                }
                if let status {
                    return String(localized: "AI could not process the request (HTTP \(status)). Try again or check the model in meeting settings.")
                }
                return String(localized: "AI could not process the request. Try again or check the model in meeting settings.")
            }
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return String(localized: "AI response timed out. Try again or check that the selected backend is available.")
        }
        if error is ChatGPTAuthError {
            return String(localized: "Sign in to ChatGPT again in Settings → Meetings → Summary backend.")
        }
        return String(localized: "Could not get an AI answer. Check your connection and Settings → Meetings → Summary backend.")
    }
}
