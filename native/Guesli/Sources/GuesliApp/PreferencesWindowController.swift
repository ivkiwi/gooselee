import AppKit
import Foundation
import GuesliCore

@MainActor
final class PreferencesWindowController: NSObject {
    private let controller: GuesliController

    init(controller: GuesliController) {
        self.controller = controller
    }

    func show() {
        controller.openHistoryWindow(tab: .settings)
    }

    func refresh() {
        controller.syncAppState()
    }
}
