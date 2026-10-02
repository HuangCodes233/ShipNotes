import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
enum OpenPanelPresenter {
    static func present(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = presentationWindow {
            panel.beginSheetModal(for: window) { response in
                completion(response, panel.url)
            }
        } else {
            let response = panel.runModal()
            completion(response, panel.url)
        }
    }

    private static var presentationWindow: NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows.map(Optional.some)
        return candidates.compactMap { $0 }.first { window in
            window.isVisible &&
            !window.isMiniaturized &&
            !(window is NSPanel) &&
            window.canBecomeKey
        }
    }
}
#endif
