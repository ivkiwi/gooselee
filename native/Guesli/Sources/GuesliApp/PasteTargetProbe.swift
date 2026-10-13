import AppKit
import ApplicationServices
import Foundation

enum PasteTargetVerdict: Equatable, Sendable {
    case target
    case none
    case unknown

    var shouldRestoreClipboard: Bool { self != .none }
    var shouldSuggestManualPaste: Bool { self == .none }
}

enum PasteTargetProbe {
    struct Attributes {
        var role: String?
        var editable: Bool?
        var valueSettable: Bool?
        var hasSelectedTextRange: Bool?
        var reliable = true
    }

    static func verdict(for attributes: Attributes) -> PasteTargetVerdict {
        if attributes.editable == true || attributes.valueSettable == true
            || attributes.hasSelectedTextRange == true {
            return .target
        }
        guard attributes.reliable, let role = attributes.role else { return .unknown }
        switch role {
        case kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole:
            return .target
        case kAXStaticTextRole, kAXImageRole:
            return .none
        default:
            // Custom controls, browser containers and table cells (Numbers, Excel) may still accept a paste.
            return .unknown
        }
    }

    static func focusedTargetVerdict() -> PasteTargetVerdict {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(axApp, 0.1)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = focused as! AXUIElement
        _ = AXUIElementSetMessagingTimeout(element, 0.1)
        var attributes = Attributes()

        func read(_ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if result != .success && result != .attributeUnsupported && result != .noValue {
                attributes.reliable = false
            }
            return result == .success ? value : nil
        }

        attributes.role = read(kAXRoleAttribute) as? String
        if let editable = read("AXEditable") {
            attributes.editable = editable as? Bool
            if attributes.editable == nil { attributes.reliable = false }
        }
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settableResult == .success {
            attributes.valueSettable = settable.boolValue
        } else if settableResult != .attributeUnsupported && settableResult != .noValue {
            attributes.reliable = false
        }
        if let rangeRef = read(kAXSelectedTextRangeAttribute) {
            if CFGetTypeID(rangeRef) == AXValueGetTypeID() {
                var range = CFRange(location: 0, length: 0)
                let validRange = AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
                    && range.location >= 0 && range.length >= 0
                attributes.hasSelectedTextRange = validRange
                if !validRange { attributes.reliable = false }
            } else {
                attributes.reliable = false
            }
        }
        return verdict(for: attributes)
    }
}

/// The paste deadline consumes UNKNOWN if the AX reply has not arrived yet.
final class PasteTargetObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var verdict: PasteTargetVerdict = .unknown

    func update(_ verdict: PasteTargetVerdict) {
        lock.withLock { self.verdict = verdict }
    }

    var current: PasteTargetVerdict { lock.withLock { verdict } }
}
