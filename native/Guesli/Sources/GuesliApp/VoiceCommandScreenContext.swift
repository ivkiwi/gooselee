import AppKit
import ApplicationServices

enum VoiceCommandScreenContext {
    static func captureAsync() -> Task<DictationContext, Never> {
        Task.detached(priority: .userInitiated) {
            DictationContextCapture.capture(forVoiceCommand: true)
        }
    }

    static func windowText(app: NSRunningApplication, focusedElement: AXUIElement, fallback: String) -> String {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        var title = ""
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            title = string(window as! AXUIElement, attribute: kAXTitleAttribute)
        }

        var range = CFRange(location: 0, length: 5_000)
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let count = count as? Int {
            range.length = min(max(count, 0), range.length)
        }
        var text: CFTypeRef?
        let rangeValue = AXValueCreate(.cfRange, &range)
        let document: String
        if let rangeValue,
           AXUIElementCopyParameterizedAttributeValue(focusedElement, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &text) == .success,
           let text = text as? String {
            document = text
        } else {
            let fullText = (count as? Int).map { $0 <= 5_000 && $0 >= 0 }
            let value = fullText == true ? string(focusedElement, attribute: kAXValueAttribute) : ""
            document = value.isEmpty ? fallback : value
        }
        return [String(title.prefix(300)), document].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func string(_ element: AXUIElement, attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
