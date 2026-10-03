import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// UI appearance preference: follow the system, or force light / dark.
enum AppearanceOption: String, CaseIterable, Identifiable {
    case system = ""
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("Follow System")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }

    /// SwiftUI color scheme to force, or nil to follow the system. Used with
    /// `.preferredColorScheme` so the SwiftUI scene (including the toolbar,
    /// which `NSApp.appearance` alone doesn't reliably refresh) matches.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppearanceManager {
    static let appStorageKey = "shipnotes.appearance"

    /// Drive the whole app's appearance via `NSApp.appearance`. Unlike the
    /// language preference, this is live — no restart needed — and it covers
    /// every window plus AppKit panels/alerts (NSOpenPanel, NSAlert), so the
    /// app never looks half-dark.
    @MainActor
    static func apply(_ option: AppearanceOption) {
        #if canImport(AppKit)
        let appearance: NSAppearance?
        switch option {
        case .system: appearance = nil  // nil = inherit the system setting
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
        #endif
    }

    @MainActor
    static func applyPersistedAtLaunch() {
        apply(current)
    }

    static var current: AppearanceOption {
        let stored = UserDefaults.standard.string(forKey: appStorageKey) ?? ""
        return AppearanceOption(rawValue: stored) ?? .system
    }
}
