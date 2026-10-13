import Foundation
import GuesliCore

@MainActor
final class MeetingPreparationScheduler {
    private var timers: [String: Timer] = [:]
    private var scheduledEvents: [String: UnifiedCalendarEvent] = [:]
    private var delivered: [String: Date] = [:]
    private var wakeActivity: NSObjectProtocol?

    func sync(
        store: DictationStore,
        events: [UnifiedCalendarEvent],
        hiddenEventIDs: Set<String>,
        enabled: Bool,
        now: Date = Date(),
        onNotify: @escaping (MeetingPreparationNotification, Int64) -> Bool
    ) {
        guard enabled else { cancel(); return }
        delivered = delivered.filter { $0.value > now }
        let candidates = ScheduledMeetingNotificationPolicy.preparationCandidates(
            from: events, now: now, hiddenEventIDs: hiddenEventIDs
        )
        var liveKeys: Set<String> = []
        for event in candidates {
            let key = event.resolvedCalendarOccurrence.identityKey + "|\(event.startDate.timeIntervalSince1970)"
            guard delivered[key] == nil,
                  notification(for: event, store: store) != nil else { continue }
            liveKeys.insert(key)
            scheduledEvents[key] = event
            guard timers[key] == nil else { continue }
            let fireDate = event.startDate.addingTimeInterval(-ScheduledMeetingNotificationPolicy.preparationLeadTime)
            let timer = Timer(timeInterval: max(fireDate.timeIntervalSince(now), 0.1), repeats: false) { [weak self] timer in
                Task { @MainActor [weak self] in
                    guard let self, self.timers[key] === timer else { return }
                    self.timers.removeValue(forKey: key)
                    self.updateWakeActivity()
                    guard let event = self.scheduledEvents.removeValue(forKey: key),
                          Date() < event.startDate,
                          Date().timeIntervalSince(fireDate) <= ScheduledMeetingNotificationPolicy.startPromptGracePeriod,
                          let (notification, predecessorID) = self.notification(for: event, store: store) else { return }
                    if onNotify(notification, predecessorID) { self.delivered[key] = event.startDate }
                }
            }
            timers[key] = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        for key in timers.keys.filter({ !liveKeys.contains($0) }) {
            timers.removeValue(forKey: key)?.invalidate()
            scheduledEvents.removeValue(forKey: key)
        }
        updateWakeActivity()
    }

    func cancel() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        scheduledEvents.removeAll()
        updateWakeActivity()
    }

    private func notification(
        for event: UnifiedCalendarEvent,
        store: DictationStore
    ) -> (MeetingPreparationNotification, Int64)? {
        guard let predecessor = try? RecurringMeetingContext.predecessor(
            in: store, occurrence: event.resolvedCalendarOccurrence, before: event.startDate
        ), predecessor.notesState == .structuredNotes,
              let notification = MeetingPreparationNotification.make(title: event.title, notes: predecessor.formattedNotes) else { return nil }
        return (notification, predecessor.id)
    }

    private func updateWakeActivity() {
        if timers.isEmpty {
            if let wakeActivity { ProcessInfo.processInfo.endActivity(wakeActivity) }
            wakeActivity = nil
        } else if wakeActivity == nil {
            wakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Preparing for scheduled meetings"
            )
        }
    }
}
