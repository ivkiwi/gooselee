import Foundation
import Testing
@testable import GuesliApp

@MainActor
@Suite("Streaming dictation stop regressions", .guesliHermeticSupport)
struct StreamingDictationStopRegressionTests {
    @Test("a streaming session owns the start gate until its completion is handled")
    func pendingStreamingSessionRejectsNewStart() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = makeController(supportDirectory: directory)
        controller.dictationTestCallback = { _ in }
        controller.isNemotron35Streaming = true

        #expect(!controller.ensureDictationBackendReady())
        #expect(controller.isNemotron35Streaming)
        controller.isNemotron35Streaming = false
        #expect(controller.ensureDictationBackendReady())
    }

    @Test("Stop before the streaming controller exists finishes in idle")
    func stopBeforeControllerReadyReturnsToIdle() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = makeController(supportDirectory: directory)
        controller.dictationTestCallback = { _ in }
        controller.isNemotron35Streaming = true

        controller.handleStop()

        #expect(!controller.isNemotron35Streaming)
        #expect(controller.appState.dictationState == .idle)
        #expect(controller.ensureDictationBackendReady())
    }

    @Test("recovery moves finalized audio outside swept temporary directories")
    func recoveryPersistsRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.wav")
        let data = Data([1, 2, 3])
        try data.write(to: source)

        let retained = try StreamingDictationRecovery.retainRecording(
            source, startedAt: Date(timeIntervalSince1970: 100), supportDirectory: directory.appendingPathComponent("support")
        )

        #expect(retained.deletingLastPathComponent().lastPathComponent == "dictation-recovery")
        #expect(try Data(contentsOf: retained) == data)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("failed recovery move preserves the original audio")
    func recoveryFailurePreservesSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.wav")
        let blockedSupport = directory.appendingPathComponent("support")
        try Data([1, 2, 3]).write(to: source)
        try Data().write(to: blockedSupport)

        #expect(throws: Error.self) {
            try StreamingDictationRecovery.retainRecording(source, startedAt: Date(), supportDirectory: blockedSupport)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeController(supportDirectory: URL) -> GuesliController {
        GuesliController(
            runtime: RuntimePaths(repoRoot: FileManager.default.temporaryDirectory, menuIcon: nil, appIcon: nil, bundlePath: nil),
            configStore: ConfigStore(supportURL: supportDirectory)
        )
    }
}
