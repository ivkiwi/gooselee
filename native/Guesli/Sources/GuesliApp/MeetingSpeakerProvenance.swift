import Foundation
import GuesliCore

extension MeetingSpeakerAttribution.Source {
    var displayLabel: String {
        switch self {
        case .user: return String(localized: "Manually Named")
        case .googleMeet: return String(localized: "Google Meet")
        case .unknown: return String(localized: "Source Unknown")
        }
    }

    var explanation: String {
        switch self {
        case .user: return String(localized: "This name was corrected manually for this transcript.")
        case .googleMeet: return String(localized: "Suggested from Google Meet events. This does not verify the speaker's identity.")
        case .unknown: return String(localized: "No name source was saved for this speaker.")
        }
    }
}
