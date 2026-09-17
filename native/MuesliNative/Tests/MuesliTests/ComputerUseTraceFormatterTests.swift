import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("Legacy Computer Use trace formatting", .muesliHermeticSupport)
struct ComputerUseTraceFormatterTests {
    @Test("hides redundant lifecycle statuses")
    func hidesRedundantLifecycleStatuses() {
        let planning = ComputerUseTraceEvent(
            kind: "planning",
            title: "Planning",
            body: "Step 1",
            status: "planning",
            step: 1
        )
        let result = ComputerUseTraceEvent(
            kind: "tool_result",
            title: "Tool result",
            body: "Clicked",
            status: "executed",
            step: 1
        )

        #expect(ComputerUseTraceFormatter.displayStatus(for: planning) == nil)
        #expect(ComputerUseTraceFormatter.displayStatus(for: result) == "executed")
    }

    @Test("formats final legacy status buckets")
    func formatsFinalStatusBuckets() {
        #expect(ComputerUseTraceFormatter.displayFinalStatus("done") == "done")
        #expect(ComputerUseTraceFormatter.displayFinalStatus("timedout") == "timed_out")
        #expect(ComputerUseTraceFormatter.displayFinalStatus("fail") == "failed")
    }
}
