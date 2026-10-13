import SwiftUI
import GuesliCore

extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .recording:
            return String(localized: "Recording")
        case .processing:
            return String(localized: "Processing")
        case .completed:
            return String(localized: "Completed")
        case .noteOnly:
            return String(localized: "Note only")
        case .failed:
            return String(localized: "Needs attention")
        }
    }

    var displayColor: Color {
        switch self {
        case .recording:
            return GuesliTheme.recording
        case .processing:
            return GuesliTheme.accent
        case .completed:
            return GuesliTheme.success
        case .noteOnly:
            return GuesliTheme.textTertiary
        case .failed:
            return GuesliTheme.transcribing
        }
    }
}
