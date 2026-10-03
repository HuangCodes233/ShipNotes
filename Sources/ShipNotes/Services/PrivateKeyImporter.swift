import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum PrivateKeyImporter {
    static func present(onImport: @escaping (Result<String, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.prompt = L("Import")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in
                do {
                    onImport(.success(try String(contentsOf: url, encoding: .utf8)))
                } catch {
                    onImport(.failure(error))
                }
            }
        }
    }
}
