import AppKit

enum MenuBarIconRenderer {

    static let gooseSize = NSSize(width: 24, height: 18)
    static let gooseUsesTemplateTint = false

    static func shouldApplyMonochromeTint(to image: NSImage) -> Bool {
        image.isTemplate
    }

    static let options: [(id: String, label: String)] = [
        ("guesli", "Goose"),
        ("mic.fill", "Microphone"),
        ("waveform", "Waveform"),
        ("bubble.left.fill", "Bubble"),
        ("text.bubble", "Speech Bubble"),
        ("pencil.line", "Pencil"),
        ("brain.head.profile", "Brain"),
        ("sparkles", "Sparkles"),
        ("headphones", "Headphones"),
        ("person.wave.2", "Meeting"),
        ("character.bubble", "Character"),
        ("doc.text", "Document"),
    ]

    /// Returns a menu bar icon for the given choice.
    /// "guesli" is the compatibility ID for the bundled GooseLee goose;
    /// anything else renders an SF Symbol.
    static func make(choice: String = "guesli") -> NSImage? {
        if choice == "guesli" {
            if let url = Bundle.main.url(forResource: "menu_goose_color", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = gooseUsesTemplateTint
                image.size = gooseSize
                return image
            }
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(systemSymbolName: choice, accessibilityDescription: "GooseLee")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}
