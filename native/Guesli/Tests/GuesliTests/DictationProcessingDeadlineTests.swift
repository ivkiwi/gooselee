import Foundation
import Testing
@testable import GuesliApp

@Suite("Dictation processing deadline")
@MainActor
struct DictationProcessingDeadlineTests {
    @MainActor
    private final class Harness {
        var now: TimeInterval = 100
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        var recoveredText: [String] = []
        lazy var deadline = DictationProcessingDeadline(
            seconds: 180,
            now: { [weak self] in self?.now ?? 0 },
            schedule: { [weak self] delay, action in self?.scheduled.append((delay, action)) }
        )

        func start() {
            deadline.start { [weak self] text in self?.recoveredText.append(text) }
        }

        func fireTimer() {
            scheduled.removeFirst().1()
        }
    }

    @Test("a stalled operation expires once and preserves text received before cleanup")
    func expiresWithRecognizedText() {
        let harness = Harness()
        harness.start()
        harness.deadline.retainRecognizedText("  Уже распознано.\n")
        harness.now += 179
        harness.fireTimer()
        #expect(harness.recoveredText.isEmpty)
        #expect(harness.scheduled.first?.0 == 1)

        harness.now += 1
        let timer = harness.scheduled.removeFirst().1
        timer()
        #expect(harness.recoveredText == ["Уже распознано."])
        timer()
        harness.deadline.retainRecognizedText("Поздний ответ")
        #expect(harness.recoveredText == ["Уже распознано."])
    }

    @Test("an ASR that never returns still releases the session")
    func expiresWithoutTextAndCancelsTask() {
        let harness = Harness()
        harness.start()
        let task = Task {}
        harness.deadline.attach(task)
        harness.now += 180
        harness.fireTimer()
        #expect(harness.recoveredText == [""])
        #expect(task.isCancelled)
    }

    @Test("completion or cancellation disarms the old timer before a new session")
    func staleTimerDoesNotAffectNewSession() {
        let old = Harness()
        old.start()
        old.deadline.retainRecognizedText("Предыдущая диктовка")
        old.deadline.cancel()

        let current = Harness()
        current.start()
        current.deadline.retainRecognizedText("Новая диктовка")
        old.now += 200
        old.fireTimer()
        #expect(old.recoveredText.isEmpty)
        #expect(current.recoveredText.isEmpty)
        current.now += 180
        current.fireTimer()
        #expect(current.recoveredText == ["Новая диктовка"])
    }
}
