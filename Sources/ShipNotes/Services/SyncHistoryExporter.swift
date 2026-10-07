import AppKit
import UniformTypeIdentifiers

@MainActor
enum SyncHistoryExporter {
    static func present(data: Data, format: SyncHistoryExportFormat, onError: @escaping (Error) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .json ? .json : .commaSeparatedText]
        panel.nameFieldStringValue = format == .json ? "ShipNotes-history.json" : "ShipNotes-history.csv"
        panel.canCreateDirectories = true
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { onError(error) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }
}
