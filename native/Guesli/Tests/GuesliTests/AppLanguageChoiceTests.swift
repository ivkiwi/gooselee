import Foundation
import Testing
@testable import GuesliApp

@Suite("App language choice", .guesliHermeticSupport)
struct AppLanguageChoiceTests {
    @Test("choices map to AppleLanguages values and back")
    func choicesRoundTrip() {
        #expect(AppLanguageChoice.system.appleLanguages == nil)
        #expect(AppLanguageChoice.english.appleLanguages == ["en"])
        #expect(AppLanguageChoice.russian.appleLanguages == ["ru"])

        for choice in AppLanguageChoice.allCases {
            #expect(AppLanguageChoice(appleLanguages: choice.appleLanguages) == choice)
        }
    }

    @Test("regional codes map to their language, unknown ones to system")
    func regionalAndUnknownCodes() {
        #expect(AppLanguageChoice(appleLanguages: ["ru-RU", "en-US"]) == .russian)
        #expect(AppLanguageChoice(appleLanguages: ["en-GB"]) == .english)
        #expect(AppLanguageChoice(appleLanguages: ["de"]) == .system)
        #expect(AppLanguageChoice(appleLanguages: []) == .system)
    }

    @Test("current reads only the app domain and apply writes or removes the override")
    func currentAndApplyUseAppDomain() throws {
        let suiteName = "com.guesli.tests.language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguageChoice.current(defaults: defaults, bundleIdentifier: suiteName) == .system)

        AppLanguageChoice.russian.apply(defaults: defaults)
        #expect(AppLanguageChoice.current(defaults: defaults, bundleIdentifier: suiteName) == .russian)

        AppLanguageChoice.system.apply(defaults: defaults)
        #expect(AppLanguageChoice.current(defaults: defaults, bundleIdentifier: suiteName) == .system)
    }
}
