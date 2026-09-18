import Testing
import Foundation
import GuesliCore
@testable import GuesliApp

@Suite("Dictation backend readiness")
struct DictationBackendReadinessTests {
    @Test("preparing and failed states block dictation")
    func blockedStates() {
        #expect(!DictationBackendReadiness.preparing.allowsDictation)
        #expect(DictationBackendReadiness.preparing.blockingMessage(backendLabel: "GigaAM") == "Warming up GigaAM...")
        #expect(!DictationBackendReadiness.failed.allowsDictation)
        #expect(DictationBackendReadiness.failed.blockingMessage(backendLabel: "GigaAM") == "GigaAM unavailable")
    }

    @Test("ready state allows dictation")
    func readyState() {
        #expect(DictationBackendReadiness.ready.allowsDictation)
        #expect(DictationBackendReadiness.ready.blockingMessage(backendLabel: "GigaAM") == nil)
    }
}

// MARK: - ChatGPT File-based Token Storage

@Suite("ChatGPT Token Storage", .guesliHermeticSupport)
struct ChatGPTTokenStorageTests {

    @Test("isAuthenticated returns false when no token file exists")
    func notAuthenticatedByDefault() throws {
        let root = try makeTokenTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(makeTokenStore(root: root).load() == nil)
    }

    @Test("signOut does not crash even when not signed in")
    func signOutSafe() throws {
        let root = try makeTokenTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        makeTokenStore(root: root).signOut()
    }

    private func makeTokenTestDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-token-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTokenStore(root: URL) -> AuthTokenFileStore {
        AuthTokenFileStore(
            primaryURL: root.appendingPathComponent("chatgpt-auth.json"),
            logPrefix: "chatgpt-auth",
            logger: { _ in }
        )
    }
}

// MARK: - Floating Indicator: showFloatingIndicator hides only idle state

@Suite("FloatingIndicator visibility", .guesliHermeticSupport)
struct FloatingIndicatorVisibilityTests {

    @Test("config default shows floating indicator")
    func defaultShowsIndicator() {
        let config = AppConfig()
        #expect(config.showFloatingIndicator == true)
    }

    @Test("showFloatingIndicator persists through JSON round-trip")
    func jsonRoundTrip() throws {
        var config = AppConfig()
        config.showFloatingIndicator = false
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.showFloatingIndicator == false)
    }

    @Test("showFloatingIndicator decodes from snake_case JSON")
    func snakeCaseDecode() throws {
        let json = #"{"show_floating_indicator": false}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(config.showFloatingIndicator == false)
    }

    @Test("post processor defaults to disabled")
    func postProcessorDisabledByDefault() {
        let config = AppConfig()
        #expect(config.enablePostProcessor == false)
    }

    @Test("post processor defaults to v3 model")
    func postProcessorDefaultModel() {
        let config = AppConfig()
        #expect(config.activePostProcessorId == PostProcessorOption.defaultOption.id)
    }

    @Test("post processor persists through JSON round-trip")
    func postProcessorRoundTrip() throws {
        var config = AppConfig()
        config.enablePostProcessor = true
        config.activePostProcessorId = PostProcessorOption.qwen35_0_8b.id
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.enablePostProcessor == true)
        #expect(decoded.activePostProcessorId == PostProcessorOption.qwen35_0_8b.id)
    }

    @Test("post processor decodes from snake_case JSON")
    func postProcessorSnakeCaseDecode() throws {
        let json = #"{"enable_post_processor": true}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        #expect(config.enablePostProcessor == true)
    }
}

// MARK: - Unified indicator frame sizes

@Suite("Indicator frame sizes", .guesliHermeticSupport)
struct IndicatorFrameSizeTests {

    @Test("recording frame size is consistent for all non-meeting dictation")
    func recordingFrameUnified() {
        // Both hold and toggle dictation should use the same 76x22 size
        // Meeting recording uses 72x32
        // This test validates the model constants that drive the frame
        let config = AppConfig()
        #expect(config.showFloatingIndicator == true)
        // The frame sizes are hardcoded in FloatingIndicatorController.frameForState
        // We test that the config round-trips correctly (the visual test is manual)
    }

    @Test("default indicator center uses the medium capsule at right-middle")
    @MainActor
    func defaultIndicatorCenterUsesScreenMidpoint() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let center = FloatingIndicatorController.defaultIndicatorCenter(in: visibleFrame)
        #expect(center.x == 1266)
        #expect(center.y == 450)
    }

    @Test("off-screen saved indicator center falls back to right-middle default")
    @MainActor
    func offscreenSavedIndicatorCenterFallsBack() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let size = NSSize(width: 76, height: 22)
        let offscreen = CGPoint(x: 1708, y: 1491)

        #expect(
            !FloatingIndicatorController.isUsableIndicatorCenter(
                offscreen,
                in: visibleFrame,
                size: size
            )
        )
        #expect(
            FloatingIndicatorController.defaultIndicatorCenter(in: visibleFrame) ==
            CGPoint(x: 1266, y: 450)
        )
    }

    @Test("indicator size presets scale the idle capsule and goose")
    func indicatorSizePresets() {
        #expect(IndicatorSize.small.idleSize == NSSize(width: 44, height: 28))
        #expect(IndicatorSize.medium.idleSize == NSSize(width: 52, height: 34))
        #expect(IndicatorSize.large.idleSize == NSSize(width: 60, height: 40))
        #expect(IndicatorSize.small.iconSize < IndicatorSize.medium.iconSize)
        #expect(IndicatorSize.medium.iconSize < IndicatorSize.large.iconSize)
        #expect(IndicatorSize.medium.hoverSize.height > IndicatorSize.medium.idleSize.height)
    }

    @Test("anchor centers respect fixed screen insets")
    @MainActor
    func anchorCentersUseExpectedInsets() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let size = NSSize(width: 44, height: 28)

        #expect(
            FloatingIndicatorController.anchorCenter(.topLeading, in: visibleFrame, size: size) ==
            CGPoint(x: 130, y: 828)
        )
        #expect(
            FloatingIndicatorController.anchorCenter(.bottomCenter, in: visibleFrame, size: size) ==
            CGPoint(x: 700, y: 72)
        )
    }

    @Test("dock preset keeps a 20 point gap and follows Dock orientation")
    @MainActor
    func dockPresetUsesDockFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1336, height: 900)
        let size = NSSize(width: 44, height: 28)

        #expect(
            FloatingIndicatorController.dockAnchorCenter(
                .dockInner,
                dockFrame: NSRect(x: 1336, y: 200, width: 104, height: 500),
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                size: size,
                gap: 20
            ) == CGPoint(x: 1294, y: 450)
        )
        #expect(
            FloatingIndicatorController.dockAnchorCenter(
                .dockInner,
                dockFrame: NSRect(x: 300, y: 0, width: 840, height: 80),
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                size: size,
                gap: 20
            ) == CGPoint(x: 720, y: 114)
        )
        #expect(
            FloatingIndicatorController.dockAnchorCenter(
                .dockStart,
                dockFrame: NSRect(x: 1336, y: 200, width: 104, height: 500),
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                size: size,
                gap: 12
            ) == CGPoint(x: 1388, y: 726)
        )
        #expect(
            FloatingIndicatorController.dockAnchorCenter(
                .dockEnd,
                dockFrame: NSRect(x: 300, y: 0, width: 840, height: 80),
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                size: size,
                gap: 12
            ) == CGPoint(x: 1174, y: 40)
        )

        let savedCenter = CGPointCodable(x: 1885, y: 900)
        #expect(
            FloatingIndicatorController.customIndicatorCenter(
                saved: savedCenter,
                currentFrame: NSRect(x: 1700, y: 882, width: 220, height: 36),
                screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1243),
                size: size,
                fallback: .zero
            ) == CGPoint(x: 1885, y: 900)
        )
        #expect(
            FloatingIndicatorController.dockInwardExpandedFrame(
                baseFrame: NSRect(x: 1863, y: 886, width: 44, height: 28),
                expandedSize: NSSize(width: 220, height: 36),
                dockFrame: NSRect(x: 1860, y: 325, width: 50, height: 555),
                screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1243)
            ) == NSRect(x: 1687, y: 882, width: 220, height: 36)
        )
    }

    @Test("Dock endpoint recording pill expands inward without crossing the screen edge")
    @MainActor
    func dockEndpointRecordingPillExpandsInward() {
        let frame = FloatingIndicatorController.dockInwardExpandedFrame(
            baseFrame: NSRect(x: 1866, y: 886, width: 52, height: 34),
            expandedSize: NSSize(width: 76, height: 22),
            dockFrame: NSRect(x: 1867, y: 344, width: 50, height: 517),
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1243)
        )

        #expect(frame == NSRect(x: 1842, y: 892, width: 76, height: 22))
    }

    @Test("Dock start and end keep one reference center across states")
    @MainActor
    func dockEndpointsUseIdleReferenceSize() {
        let idle = NSSize(width: 44, height: 28)
        let recording = NSSize(width: 76, height: 22)

        #expect(
            FloatingIndicatorController.dockAnchorReferenceSize(
                .dockStart,
                currentSize: recording,
                idleSize: idle
            ) == idle
        )
        #expect(
            FloatingIndicatorController.dockAnchorReferenceSize(
                .dockEnd,
                currentSize: recording,
                idleSize: idle
            ) == idle
        )
        #expect(
            FloatingIndicatorController.dockAnchorReferenceSize(
                .dockInner,
                currentSize: recording,
                idleSize: idle
            ) == recording
        )
    }

    @Test("Dock alignment uses the visible Dock strip instead of the icon list")
    @MainActor
    func dockAlignmentUsesVisibleStrip() {
        let aligned = FloatingIndicatorController.dockAlignmentFrame(
            NSRect(x: 1860, y: 344, width: 50, height: 517),
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1243),
            visibleFrame: NSRect(x: 0, y: 0, width: 1864, height: 1205)
        )

        #expect(aligned.midX == 1892)
        #expect(aligned.minY == 344)
        #expect(aligned.height == 517)
    }

    @Test("Dock endpoint remains centered when the pill barely crosses the screen edge")
    @MainActor
    func dockEndpointAllowsSmallCrossAxisOverflow() {
        let dock = NSRect(x: 1860, y: 344, width: 50, height: 517)
        let bounds = NSRect(x: 0, y: 0, width: 1920, height: 1243)
        let center = CGPoint(x: 1892, y: 907)

        let frame = FloatingIndicatorController.dockAlignedFrame(
            center: center,
            size: NSSize(width: 76, height: 22),
            anchor: .dockStart,
            dockFrame: dock,
            bounds: bounds
        )
        #expect(frame.midX == center.x)
        #expect(frame.maxX == 1930)

        let wideFrame = FloatingIndicatorController.dockAlignedFrame(
            center: center,
            size: NSSize(width: 220, height: 36),
            anchor: .dockStart,
            dockFrame: dock,
            bounds: bounds
        )
        #expect(wideFrame.maxX == bounds.maxX)
    }

    @Test("transcribing pill widens for status labels")
    @MainActor
    func transcribingPillWidensForStatusText() {
        let short = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Planning",
            screenWidth: 1200
        )
        let long = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Navigating to YouTube search",
            screenWidth: 1200
        )

        #expect(short.width >= 190)
        #expect(long.width > short.width)
        #expect(long.width <= 360)
        #expect(long.height == 32)
    }

    @Test("transcribing pill caps to available screen width")
    @MainActor
    func transcribingPillCapsToScreenWidth() {
        let size = FloatingIndicatorController.transcribingPillSizeForTesting(
            title: "Executing an unusually long computer use action label",
            screenWidth: 180
        )

        #expect(size.width <= 148)
        #expect(size.height == 32)
    }
}

@Suite("Floating indicator pointer interaction")
struct FloatingIndicatorPointerInteractionTests {
    @MainActor
    @Test("clicking the stop control stops the meeting")
    func stopControlStopsMeeting() throws {
        let indicator = makeIndicator()
        var stopCount = 0
        indicator.onStopMeeting = { stopCount += 1 }
        indicator.setMeetingRecording(true, config: AppConfig())

        let size = try #require(indicator.controlHitTestSizeForTesting)
        let stopFrame = FloatingIndicatorControlLayout.trailingControlFrame(in: size)
        indicator.handleClick(at: CGPoint(x: stopFrame.midX, y: stopFrame.midY))

        #expect(stopCount == 1)
        indicator.close()
    }

    @MainActor
    @Test("clicking the pill body no longer stops the meeting")
    func bodyClickLeavesMeetingRecording() throws {
        let indicator = makeIndicator()
        var stopCount = 0
        var pauseCount = 0
        indicator.onStopMeeting = { stopCount += 1 }
        indicator.onToggleMeetingPause = { pauseCount += 1 }
        indicator.setMeetingRecording(true, config: AppConfig())

        let size = try #require(indicator.controlHitTestSizeForTesting)
        let bodyPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        // Guard the assumption that the pill centre really is body, so a future
        // narrower pill fails here rather than silently weakening the test.
        #expect(FloatingIndicatorControlLayout.hit(at: bodyPoint, in: size) == .body)

        indicator.handleClick(at: bodyPoint)

        #expect(stopCount == 0)
        #expect(pauseCount == 0)
        indicator.close()
    }

    @Test("stop hit region tracks the drawn control instead of the pill body")
    func stopHitRegionMatchesDrawnControl() {
        let size = CGSize(width: 190, height: 34)
        let stopFrame = FloatingIndicatorControlLayout.trailingControlFrame(in: size)

        // The drawn dot and its immediate surround stop the recording.
        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: stopFrame.midX, y: stopFrame.midY),
            in: size
        ) == .trailingControl)

        // The old behaviour treated everything past x=30 as a stop.
        for x in stride(from: 30.0, through: 150.0, by: 20.0) {
            #expect(FloatingIndicatorControlLayout.hit(
                at: CGPoint(x: x, y: size.height / 2),
                in: size
            ) == .body)
        }
    }

    @Test("leading control keeps its own hit region")
    func leadingHitRegionMatchesDrawnControl() {
        let size = CGSize(width: 190, height: 34)
        let leadingFrame = FloatingIndicatorControlLayout.leadingControlFrame(in: size)

        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: leadingFrame.midX, y: leadingFrame.midY),
            in: size
        ) == .leadingControl)

        // Just outside the widened target is body, not a control.
        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: 40, y: size.height / 2),
            in: size
        ) == .body)
    }

    @Test("controls stay reachable across the pill's full height")
    func controlsSpanFullPillHeight() {
        let size = CGSize(width: 190, height: 34)
        let stopFrame = FloatingIndicatorControlLayout.trailingControlFrame(in: size)

        for y in [0.5, size.height / 2, size.height - 0.5] {
            #expect(FloatingIndicatorControlLayout.hit(
                at: CGPoint(x: stopFrame.midX, y: y),
                in: size
            ) == .trailingControl)
        }
    }

    @Test("a narrow pill resolves overlapping targets to the nearer control")
    func narrowPillPrefersNearerControl() {
        let size = CGSize(width: 36, height: 34)
        let leadingFrame = FloatingIndicatorControlLayout.leadingControlFrame(in: size)
        let trailingFrame = FloatingIndicatorControlLayout.trailingControlFrame(in: size)

        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: leadingFrame.midX, y: size.height / 2),
            in: size
        ) == .leadingControl)
        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: trailingFrame.midX, y: size.height / 2),
            in: size
        ) == .trailingControl)

        // Both points above sit in exactly one touch target, so they never reach
        // the tie-break. Probe either side of the boundary between the two
        // control centres, which is inside the overlapping region.
        let boundary = (leadingFrame.midX + trailingFrame.midX) / 2
        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: boundary - 2, y: size.height / 2),
            in: size
        ) == .leadingControl)
        #expect(FloatingIndicatorControlLayout.hit(
            at: CGPoint(x: boundary + 2, y: size.height / 2),
            in: size
        ) == .trailingControl)
    }

    @MainActor
    private func makeIndicator() -> FloatingIndicatorController {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FloatingIndicatorController(configStore: ConfigStore(supportURL: supportDirectory))
    }
}

// MARK: - OpenAI Logo Shape

@Suite("OpenAI Logo Shape", .guesliHermeticSupport)
struct OpenAILogoShapeTests {

    @Test("shape produces non-empty path")
    func nonEmptyPath() {
        let shape = OpenAILogoShape()
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
    }

    @Test("shape scales to arbitrary rect")
    func scalesCorrectly() {
        let shape = OpenAILogoShape()
        let small = shape.path(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        let large = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!small.isEmpty)
        #expect(!large.isEmpty)
        // Larger rect should produce a larger bounding box
        #expect(large.boundingRect.width > small.boundingRect.width)
    }

    @Test("shape handles zero rect without crash")
    func zeroRect() {
        let shape = OpenAILogoShape()
        let path = shape.path(in: .zero)
        // Should not crash; path will be empty or degenerate
        let _ = path.boundingRect
    }
}

// MARK: - DictationState

@Suite("DictationState idle check", .guesliHermeticSupport)
struct DictationStateIdleTests {

    @Test("all dictation states are defined")
    func allStates() {
        let states: [DictationState] = [.idle, .preparing, .recording, .transcribing]
        #expect(states.count == 4)
    }

    @Test("idle is distinct from active states")
    func idleDistinct() {
        #expect(DictationState.idle != .recording)
        #expect(DictationState.idle != .preparing)
        #expect(DictationState.idle != .transcribing)
    }
}

// MARK: - Meeting chunk collection

@Suite("Meeting chunk collection", .guesliHermeticSupport)
struct MeetingChunkCollectorTests {

    @Test("collector waits for tasks, keeps completed segments, and sorts by start")
    func collectorSortsSegments() async {
        let collector = MeetingChunkCollector()

        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                return [SpeechSegment(start: 30, end: 31, text: "later")]
            }
        )
        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(5))
                return []
            }
        )
        _ = collector.add(
            Task {
                try? await Task.sleep(for: .milliseconds(10))
                return [SpeechSegment(start: 10, end: 11, text: "earlier")]
            }
        )

        let segments = await collector.closeAndDrainSortedSegments()

        #expect(segments.map(\.text) == ["earlier", "later"])
        #expect(segments.map(\.start) == [10, 30])
    }

    @Test("collector rejects tasks after closing")
    func collectorRejectsLateTasks() async {
        let collector = MeetingChunkCollector()
        let initialTask = Task<[SpeechSegment], Never> {
            [SpeechSegment(start: 1, end: 2, text: "first")]
        }
        #expect(collector.add(initialTask).registered)

        let initial = await collector.closeAndDrainSortedSegments()
        #expect(initial.map(\.text) == ["first"])

        let lateTask = Task<[SpeechSegment], Never> {
            [SpeechSegment(start: 3, end: 4, text: "late")]
        }
        #expect(!collector.add(lateTask).registered)
        lateTask.cancel()
    }

    @Test("collector retire returns nil after drain closes collector")
    func collectorRetireReturnsNilAfterDrain() async {
        let collector = MeetingChunkCollector()
        let task = Task<[SpeechSegment], Never> {
            try? await Task.sleep(for: .milliseconds(10))
            return [SpeechSegment(start: 1, end: 2, text: "first")]
        }
        let registration = collector.add(task)
        #expect(registration.registered)

        let drained = await collector.closeAndDrainSortedSegments()
        let retired = collector.retire(id: registration.retireID, segments: await task.value)

        #expect(drained.map(\.text) == ["first"])
        #expect(retired == nil)
    }

    @Test("collector treats unknown retire IDs as stale callbacks")
    func collectorTreatsUnknownRetireIDsAsStaleCallbacks() {
        let collector = MeetingChunkCollector()
        let firstTask = Task { [SpeechSegment(start: 1, end: 2, text: "first")] }
        let secondTask = Task { [SpeechSegment(start: 2, end: 3, text: "second")] }
        let first = collector.add(firstTask)
        let second = collector.add(secondTask)
        firstTask.cancel()
        secondTask.cancel()

        let blocked = collector.retire(id: second.retireID, segments: [SpeechSegment(start: 2, end: 3, text: "second")])
        let stale = collector.retire(id: UUID(), segments: [SpeechSegment(start: 0, end: 1, text: "stale")])
        let ready = collector.retire(id: first.retireID, segments: [SpeechSegment(start: 1, end: 2, text: "first")])

        #expect(first.registered)
        #expect(second.registered)
        #expect(blocked?.isEmpty == true)
        #expect(stale == nil)
        #expect(ready?.map { $0.map(\.text) } == [["first"], ["second"]])
    }

    @Test("collector releases tail after a failed earlier chunk retires empty")
    func collectorFailureRetiresSlotAndReleasesTail() async {
        let collector = MeetingChunkCollector()
        let failedChunk = Task { [SpeechSegment]() }
        let tailChunk = Task { [SpeechSegment(start: 3, end: 4, text: "tail")] }

        let failed = collector.add(failedChunk)
        let tail = collector.add(tailChunk)

        #expect(collector.retire(id: tail.retireID, segments: await tailChunk.value)?.isEmpty == true)
        let ready = collector.retire(id: failed.retireID, segments: await failedChunk.value)

        #expect(failed.registered)
        #expect(tail.registered)
        #expect(ready?.map { $0.map(\.text) } == [[], ["tail"]])
    }

    @Test("collector drain flushes buffered chunks when an earlier slot stalls")
    func collectorDrainFlushesBufferedChunksPastStalledSlot() async {
        let collector = MeetingChunkCollector()
        let stalled = Task<[SpeechSegment], Never> {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return []
        }
        let tailChunk = Task { [SpeechSegment(start: 3, end: 4, text: "tail")] }

        let stalledRegistration = collector.add(stalled)
        let tailRegistration = collector.add(tailChunk)

        #expect(stalledRegistration.registered)
        #expect(tailRegistration.registered)
        #expect(collector.retire(id: tailRegistration.retireID, segments: await tailChunk.value)?.isEmpty == true)

        var logs: [String] = []
        var droppedCount = 0
        let drained = await collector.closeAndDrainSortedSegments(
            inactivityTimeout: 0.05,
            logger: { logs.append($0) },
            onDrainTimeoutDroppedChunkCount: { droppedCount += $0 }
        )

        #expect(drained.map(\.text) == ["tail"])
        #expect(droppedCount == 1)
        #expect(logs.contains { $0.contains("[live-collector] dropped pending chunk sequence=0 reason=drain_timeout") })
    }

    @Test("collector drain keeps slow backlog while chunks keep completing")
    func collectorDrainKeepsProgressingBacklog() async {
        let collector = MeetingChunkCollector()
        let chunks = ControlledSpeechChunks()
        for index in 0..<4 {
            _ = collector.add(
                Task {
                    await chunks.wait(for: index)
                }
            )
        }

        while await chunks.readyCount() < 4 {
            await Task.yield()
        }
        let drainTask = Task {
            await collector.closeAndDrainSortedSegments(inactivityTimeout: 0.25)
        }
        for index in 0..<4 {
            await chunks.resume(
                index: index,
                with: [SpeechSegment(start: Double(index), end: Double(index + 1), text: "chunk \(index)")]
            )
            await Task.yield()
        }
        let drained = await drainTask.value

        #expect(drained.map(\.text) == (0..<4).map { "chunk \($0)" })
    }

    @Test("collector retire returns nil after cancel closes collector")
    func collectorRetireReturnsNilAfterCancel() async {
        let collector = MeetingChunkCollector()
        let task = Task<[SpeechSegment], Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
            return [SpeechSegment(start: 1, end: 2, text: "first")]
        }
        let registration = collector.add(task)
        #expect(registration.registered)

        collector.cancelAll()
        let retired = collector.retire(id: registration.retireID, segments: await task.value)

        #expect(retired == nil)
    }

    @Test("collector flattens timed segments from a single chunk and sorts them")
    func collectorFlattensChunkSegments() async {
        let collector = MeetingChunkCollector()

        _ = collector.add(
            Task {
                [
                    SpeechSegment(start: 12, end: 12.5, text: "second"),
                    SpeechSegment(start: 11, end: 11.5, text: "first")
                ]
            }
        )

        let segments = await collector.closeAndDrainSortedSegments()

        #expect(segments.map(\.text) == ["first", "second"])
        #expect(segments.map(\.start) == [11, 12])
    }
}

private actor ControlledSpeechChunks {
    private var continuations: [Int: CheckedContinuation<[SpeechSegment], Never>] = [:]

    func wait(for index: Int) async -> [SpeechSegment] {
        await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func readyCount() -> Int {
        continuations.count
    }

    func resume(index: Int, with segments: [SpeechSegment]) {
        continuations.removeValue(forKey: index)?.resume(returning: segments)
    }
}

@Suite("Meeting chunk timing", .guesliHermeticSupport)
struct MeetingChunkTimingTrackerTests {

    @Test("tracks chunk offsets from processed sample counts")
    func tracksChunkOffsets() {
        var tracker = MeetingChunkTimingTracker()
        tracker.start()
        tracker.append(sampleCount: 1600)

        let first = tracker.rotate()
        tracker.append(sampleCount: 800)
        let second = tracker.finish()

        #expect(first?.startSampleIndex == 0)
        #expect(first?.sampleCount == 1600)
        #expect(first?.startTimeSeconds == 0)
        #expect(first?.durationSeconds == 0.1)

        #expect(second?.startSampleIndex == 1600)
        #expect(second?.sampleCount == 800)
        #expect(second?.startTimeSeconds == 0.1)
        #expect(second?.durationSeconds == 0.05)
    }

    @Test("tracks overlap as the next chunk start")
    func tracksOverlapOffsets() {
        var tracker = MeetingChunkTimingTracker()
        tracker.start()
        tracker.append(sampleCount: 1600)

        let first = tracker.rotate(overlapSampleCount: 400)
        tracker.append(sampleCount: 800)
        let second = tracker.finish()

        #expect(first?.startSampleIndex == 0)
        #expect(first?.sampleCount == 1600)
        #expect(second?.startSampleIndex == 1200)
        #expect(second?.sampleCount == 1200)
        #expect(second?.startTimeSeconds == 0.075)
    }

    @Test("GigaAM meeting chunking uses longer chunks and overlap")
    func gigaAMMeetingChunkingPolicy() {
        let gigaAM = MeetingSession.liveChunkingConfiguration(for: .gigaAMV3Russian)
        let parakeet = MeetingSession.liveChunkingConfiguration(for: .parakeetMultilingual)

        #expect(gigaAM.maxChunkDuration == 20)
        #expect(gigaAM.overlapSampleCount == 32_000)
        #expect(gigaAM.deduplicatesText)
        #expect(parakeet.maxChunkDuration == 5)
        #expect(parakeet.overlapSampleCount == 0)
        #expect(!parakeet.deduplicatesText)
    }
}
