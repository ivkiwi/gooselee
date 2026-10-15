import Foundation

public enum MeetingProcessingOperation: String, Codable, Sendable {
    case initial, retranscription, summary
}

public enum MeetingProcessingOutcome: String, Codable, Sendable {
    case running, succeeded, failed, cancelled, interrupted
}

public enum MeetingSourceCompleteness: String, Codable, Sendable {
    case unknown, incomplete
}

/// Technical facts only: never include prompts, transcript text, contacts, paths or credentials.
public struct MeetingProcessingConfiguration: Codable, Equatable, Sendable {
    public var asrBackend: String?
    public var asrModel: String?
    public var summaryBackend: String?
    public var summaryModel: String?
    public var cleanupModel: String?
    public var diarizationEnabled: Bool
    public var audioSources: [String]
    public var completeness: MeetingSourceCompleteness
    public var warnings: [String]
    public var templateID: String?
    public var summaryRetryCount: Int?

    public init(asrBackend: String? = nil, asrModel: String? = nil,
                summaryBackend: String? = nil, summaryModel: String? = nil,
                cleanupModel: String? = nil, diarizationEnabled: Bool = false,
                audioSources: [String] = [], completeness: MeetingSourceCompleteness = .unknown,
                warnings: [String] = []) {
        self.asrBackend = asrBackend; self.asrModel = asrModel
        self.summaryBackend = summaryBackend; self.summaryModel = summaryModel
        self.cleanupModel = cleanupModel; self.diarizationEnabled = diarizationEnabled
        self.audioSources = audioSources; self.completeness = completeness; self.warnings = warnings
        self.templateID = nil; self.summaryRetryCount = nil
    }
}

public struct MeetingProcessingAttempt: Identifiable, Codable, Sendable {
    public let id: String
    public let meetingID: Int64
    public let operation: MeetingProcessingOperation
    public let startedAt: Double
    public let endedAt: Double?
    public let outcome: MeetingProcessingOutcome
    public let stage: String
    public let configuration: MeetingProcessingConfiguration
    public let inputRevision: Int64
    public let safeError: String?
}

public enum MeetingProcessingError: Error, LocalizedError {
    case alreadyRunning, staleInput, emptyResult
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return String(localized: "This meeting is already being processed.")
        case .staleInput: return String(localized: "The meeting changed during processing. Retry using the current text.")
        case .emptyResult: return String(localized: "The model returned no usable result. Your saved text is unchanged.")
        }
    }
}
