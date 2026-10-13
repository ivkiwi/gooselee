import AppKit
import ApplicationServices
import Foundation
import GuesliCore

enum PasteController {
    /// How long to wait after simulating Cmd+V before restoring the clipboard.
    /// The receiving app must have consumed the paste data within this window.
    private static let clipboardRestoreDelay: TimeInterval = 0.5

    /// Paste text into the active app, restoring the clipboard unless AX confirms no text target.
    ///
    /// Flow: save clipboard → write text → Cmd+V → restore clipboard after delay.
    /// If the clipboard cannot be saved (e.g. lazy-provided data), falls back to a simple
    /// paste without restoration.
    static func paste(
        text: String,
        appendDictationSentenceSpace: Bool = false,
        pasteboard: NSPasteboard = .general,
        shortcut: PasteShortcut = .commandV,
        simulatePasteAction: (() -> Void)? = nil,
        pasteTargetCheck: @escaping @Sendable () -> PasteTargetVerdict = PasteTargetProbe.focusedTargetVerdict,
        onNoTarget: (() -> Void)? = nil
    ) {
        guard !text.isEmpty else { return }
        let simulate = simulatePasteAction ?? { simulatePaste(shortcut: shortcut) }

        // Save current clipboard contents (all types) so we can restore after paste.
        let savedItems = saveClipboard(pasteboard)

        pasteboard.clearContents()
        // Only live dictation opts in. Computer Use and other paste callers keep
        // their exact text; stored transcripts are never padded.
        let pastedText = appendDictationSentenceSpace
            ? text + DictationPasteSpacing.trailingSeparator(after: text)
            : text
        pasteboard.setString(pastedText, forType: .string)
        let pasteChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulate()
            let target = PasteTargetObservation()
            DispatchQueue.global(qos: .userInitiated).async {
                target.update(pasteTargetCheck())
            }

            // Restore the original clipboard contents after the receiving app has consumed the paste.
            DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
                guard pasteboard.changeCount == pasteChangeCount else { return }
                let verdict = target.current
                if verdict.shouldSuggestManualPaste { onNoTarget?() }
                guard verdict.shouldRestoreClipboard else { return }
                restoreClipboard(pasteboard, from: savedItems)
            }
        }
    }

    /// Type text directly via CGEvent keyboard simulation without touching the clipboard.
    /// Unicode events preserve the dictated characters regardless of the keyboard layout.
    static func typeText(_ text: String, postEvent: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        guard !text.isEmpty else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            fputs("[guesli-native] failed to create event source for typeText\n", stderr)
            return
        }
        for char in text {
            postUnicodeCharacter(source: source, char: char, postEvent: postEvent)
        }
    }

    // MARK: - Private

    static func eventFlags(for shortcut: PasteShortcut) -> CGEventFlags {
        switch shortcut {
        case .commandV: return .maskCommand
        case .commandShiftV: return [.maskCommand, .maskShift]
        }
    }

    private static func simulatePaste(shortcut: PasteShortcut = .commandV) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            fputs("[guesli-native] failed to create event source for paste\n", stderr)
            return
        }
        let keyCode: CGKeyCode = 9 // V
        let flags = eventFlags(for: shortcut)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        commandDown?.flags = flags
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        commandUp?.flags = flags
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }

    private static func postUnicodeCharacter(source: CGEventSource, char: Character, postEvent: (CGEvent) -> Void) {
        var utf16 = Array(char.utf16)
        utf16.withUnsafeMutableBufferPointer { buf in
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            postEvent(keyDown)
            postEvent(keyUp)
        }
    }

    /// Snapshot every item on the pasteboard so we can put it back later.
    /// Returns an array of (type, data) pairs for each item.
    /// Note: Lazy/promised clipboard providers may return nil for some types —
    /// those types are skipped, so restoration may be partial for apps that use
    /// deferred clipboard rendering.
    private static func saveClipboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in items {
            var pairs: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type, data))
                }
            }
            if !pairs.isEmpty {
                saved.append(pairs)
            }
        }
        return saved
    }

    /// Restore previously saved clipboard contents. If nothing was saved, clears the clipboard
    /// so dictation text doesn't linger.
    private static func restoreClipboard(_ pasteboard: NSPasteboard, from saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        pasteboard.clearContents()
        if saved.isEmpty { return }
        var restoredItems: [NSPasteboardItem] = []
        for itemPairs in saved {
            let item = NSPasteboardItem()
            for (type, data) in itemPairs {
                item.setData(data, forType: type)
            }
            restoredItems.append(item)
        }
        pasteboard.writeObjects(restoredItems)
    }
}
