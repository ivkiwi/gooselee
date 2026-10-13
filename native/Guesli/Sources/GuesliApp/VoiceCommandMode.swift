import AppKit

struct VoiceCommandMode {
    private(set) var isCommand = false
    private var isHandsFree = false

    static func supportsHotkey(keyCode: UInt16, requiredModifiers: NSEvent.ModifierFlags?) -> Bool {
        keyCode != 56 && keyCode != 60 && requiredModifiers?.contains(.shift) != true
    }

    mutating func begin(enabled: Bool, shiftDown: Bool, handsFree: Bool) {
        isCommand = enabled && shiftDown
        isHandsFree = handsFree
    }

    mutating func observeShift(enabled: Bool, shiftDown: Bool, hotkeyHeld: Bool) {
        guard enabled, shiftDown, hotkeyHeld, !isHandsFree else { return }
        isCommand = true
    }

    static func matchesCombination(
        _ flags: NSEvent.ModifierFlags,
        required: NSEvent.ModifierFlags,
        commandsEnabled: Bool
    ) -> Bool {
        let actual = HotkeyConfig.supportedCombinationModifiers(from: flags)
        return actual == required
            || (commandsEnabled && actual == required.union(.shift))
    }
}
