import ApplicationServices
import Testing
@testable import GuesliApp

@Suite("Paste target policy")
struct PasteTargetProbeTests {
    @Test("only a definite missing target retains the clipboard and suggests manual paste", arguments: [
        PasteTargetVerdict.target, .none, .unknown,
    ])
    func verdictDecision(verdict: PasteTargetVerdict) {
        #expect(verdict.shouldRestoreClipboard == (verdict != .none))
        #expect(verdict.shouldSuggestManualPaste == (verdict == .none))
    }

    @Test("native text roles accept paste", arguments: [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole])
    func nativeTextRole(role: String) {
        #expect(PasteTargetProbe.verdict(for: .init(role: role)) == .target)
    }

    @Test("static content and file lists have no text target", arguments: [
        kAXStaticTextRole, kAXImageRole, kAXListRole, kAXTableRole, kAXOutlineRole,
    ])
    func staticRole(role: String) {
        #expect(PasteTargetProbe.verdict(for: .init(role: role)) == .none)
    }

    @Test("each text capability wins over a static role")
    func textCapabilities() {
        #expect(PasteTargetProbe.verdict(for: .init(role: kAXStaticTextRole, editable: true)) == .target)
        #expect(PasteTargetProbe.verdict(for: .init(role: kAXTableRole, valueSettable: true)) == .target)
        #expect(PasteTargetProbe.verdict(for: .init(role: kAXListRole, hasSelectedTextRange: true)) == .target)
    }

    @Test("missing roles, opaque containers and AX errors remain uncertain")
    func uncertainty() {
        #expect(PasteTargetProbe.verdict(for: .init()) == .unknown)
        #expect(PasteTargetProbe.verdict(for: .init(role: kAXGroupRole, editable: false, valueSettable: false)) == .unknown)
        #expect(PasteTargetProbe.verdict(for: .init(role: "AXWebArea")) == .unknown)
        #expect(PasteTargetProbe.verdict(for: .init(role: kAXListRole, reliable: false)) == .unknown)
    }

    @Test("a delayed AX observation starts uncertain")
    func delayedObservation() {
        let observation = PasteTargetObservation()
        #expect(observation.current == .unknown)
        observation.update(.none)
        #expect(observation.current == .none)
    }
}
