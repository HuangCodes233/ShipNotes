import SwiftUI

private let _languageBootstrap: Void = {
    LanguageManager.applyPersistedLanguageAtLaunch()
}()

@main
struct ShipNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()

    init() {
        _ = _languageBootstrap
    }

    var body: some Scene {
        WindowGroup("ShipNotes") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { url in state.importURL(url) }
                .task { await state.bootstrapForLaunch() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L("Import Folder…")) { state.presentImportPickerForCurrentWorkspace() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                // ⌘⇧R (not ⌘R): this spends an AI call, so it shouldn't sit on
                // the muscle-memory "reload" slot.
                Button(L("Ask AI to re-parse")) { state.askAIToReparseCurrentWorkspace() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                // `performDryRun` / `performSync` check the same conditions as
                // the bottom bar's buttons and do nothing otherwise. Reading
                // those conditions here for `.disabled` would re-evaluate the
                // App body (and rebuild the menu) on every keystroke.
                Button(L("Dry Run")) { state.performDryRun() }
                    .keyboardShortcut("d", modifiers: .command)
                // ⌘⇧S (not ⌘S): ⌘S is Save in every Mac user's fingers — an
                // accidental hit must not start a live App Store upload.
                Button(L("Sync All")) { state.performSync() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the saved light/dark/system preference before windows show
        // so there's no flash of the wrong appearance.
        AppearanceManager.applyPersistedAtLaunch()
    }
}
