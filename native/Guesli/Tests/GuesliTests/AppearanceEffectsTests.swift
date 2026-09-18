import Testing
import AppKit
@testable import GuesliApp

@Suite("SoundController", .guesliHermeticSupport)
@MainActor
struct SoundControllerTests {

    @Test("playDictationStart with enabled=false does not throw")
    func playStartDisabled() {
        // NSSound.play() is a no-op in the test runner (no audio device required)
        SoundController.playDictationStart(enabled: false)
    }

    @Test("playDictationInsert with enabled=false does not throw")
    func playInsertDisabled() {
        SoundController.playDictationInsert(enabled: false)
    }

    @Test("playDictationStart with enabled=true does not throw")
    func playStartEnabled() {
        SoundController.playDictationStart(enabled: true)
    }

    @Test("playDictationInsert with enabled=true does not throw")
    func playInsertEnabled() {
        SoundController.playDictationInsert(enabled: true)
    }
}

@Suite("MenuBarIconRenderer", .guesliHermeticSupport)
struct MenuBarIconRendererTests {

    @Test("options keep the compatibility ID but present it as the goose")
    func optionsExposeGoose() {
        let goose = MenuBarIconRenderer.options.first { $0.id == "guesli" }
        #expect(goose?.label == "Goose")
    }

    @Test("make(choice:) returns a non-nil image for SF Symbol")
    func makeReturnsImage() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect(image != nil)
    }

    @Test("make(choice:) returns a template image for menu bar adaptation")
    func makeIsTemplate() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect(image?.isTemplate == true)
    }

    @Test("bundled goose preserves its colors and wide proportions")
    func goosePreservesColorAndWidth() {
        #expect(MenuBarIconRenderer.gooseUsesTemplateTint == false)
        #expect(MenuBarIconRenderer.gooseSize == NSSize(width: 24, height: 18))
    }

    @Test("monochrome tint applies only to template images")
    func monochromeTintFollowsTemplateFlag() {
        let colored = NSImage(size: NSSize(width: 24, height: 18))
        colored.isTemplate = false
        #expect(MenuBarIconRenderer.shouldApplyMonochromeTint(to: colored) == false)

        let template = NSImage(size: NSSize(width: 18, height: 18))
        template.isTemplate = true
        #expect(MenuBarIconRenderer.shouldApplyMonochromeTint(to: template) == true)
    }

    @Test("make(choice:) returns a non-zero size image")
    func makeHasSize() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }
}
