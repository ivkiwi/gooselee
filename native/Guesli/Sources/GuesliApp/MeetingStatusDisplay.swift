import SwiftUI
import GuesliCore

extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .noteOnly:
            return "Note only"
        case .failed:
            return "Needs attention"
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
