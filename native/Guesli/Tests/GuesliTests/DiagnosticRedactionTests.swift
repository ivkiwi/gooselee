import Testing
@testable import GuesliApp

@Suite("Diagnostic redaction")
struct DiagnosticRedactionTests {
    @Test("opaque IDs hide the room URL but stay stable for correlation")
    func opaqueIDHidesRoomURL() {
        let room = "googleMeet:meet.google.com/abc-defg-hij"
        let token = DiagnosticRedaction.opaqueID(room)

        #expect(!token.contains("abc-defg-hij"))
        #expect(token.count == 12)
        #expect(DiagnosticRedaction.opaqueID(room) == token)
        #expect(DiagnosticRedaction.opaqueID("googleMeet:meet.google.com/zzz-yyyy-xxx") != token)
    }
}
