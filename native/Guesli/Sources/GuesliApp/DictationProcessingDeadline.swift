import Foundation

/// Independent of ASR cancellation: a stalled backend must not own the hotkey forever.
@MainActor
final class DictationProcessingDeadline {
    private let seconds: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var expiresAt: TimeInterval?
    private var recognizedText = ""
    private var onTimeout: ((String) -> Void)?
    private var task: Task<Void, Never>?

    init(
        seconds: TimeInterval = 180,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    ) {
        self.seconds = seconds
        self.now = now
        self.schedule = schedule
    }

    func start(onTimeout: @escaping (String) -> Void) {
        cancel()
        recognizedText = ""
        expiresAt = now() + seconds
        self.onTimeout = onTimeout
        scheduleCheck(after: seconds)
    }

    func retainRecognizedText(_ text: String) {
        guard expiresAt != nil else { return }
        recognizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func attach(_ task: Task<Void, Never>) {
        guard expiresAt != nil else {
            task.cancel()
            return
        }
        self.task = task
    }

    func cancel() {
        expiresAt = nil
        onTimeout = nil
        task?.cancel()
        task = nil
    }

    private func scheduleCheck(after delay: TimeInterval) {
        schedule(delay) { [weak self] in self?.checkDeadline() }
    }

    private func checkDeadline() {
        guard let expiresAt else { return }
        let remaining = expiresAt - now()
        if remaining > 0 {
            scheduleCheck(after: remaining)
            return
        }
        let action = onTimeout
        let text = recognizedText
        cancel()
        action?(text)
    }
}
