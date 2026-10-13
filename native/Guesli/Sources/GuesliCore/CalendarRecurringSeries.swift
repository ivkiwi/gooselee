import Foundation

extension CalendarOccurrenceReference {
    public var recurringSeriesKeyPrefix: String? {
        guard seriesID != nil else { return nil }
        return CalendarRecurringSeries.keyPrefix(from: identityKey)
    }
}

enum CalendarRecurringSeries {
    static func keyPrefix(from identityKey: String) -> String? {
        let components = identityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 6, components[0] == "v1", components[1] == "recurring" else { return nil }
        return components.dropLast().joined(separator: "|") + "|"
    }
}
