import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum LanguageOption: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: return L("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .japanese: return "日本語"
        }
    }
}

/// Resolve a localized string from the SwiftPM module bundle, honoring the
/// user's UI-language preference (or system locale when "Follow System").
///
/// Pass additional args to interpolate via `String(format:)` — useful for
/// templates with `%d`, `%@`, `%1$d %2$d`, etc.
func L(_ key: String, _ arguments: any CVarArg...) -> String {
    let template = localizedTemplate(for: key)
    if arguments.isEmpty { return template }
    // Intentionally no `locale:` — we want %d to emit plain integers like
    // "4000", not the locale's thousands-grouped form like "4,000".
    return String(format: template, arguments: arguments)
}

/// SwiftPM places its resource bundle next to the executable for CLI runs
/// (which `Bundle.module` already handles), but inside `Contents/Resources/`
/// when we wrap into a real `.app` (so the bundle is properly code-signable).
/// Probe the conventional `.app` location first, fall back to `.module`.
private let resourceBundle: Bundle = {
    if let url = Bundle.main.url(forResource: "ShipNotes_ShipNotes", withExtension: "bundle"),
        let bundle = Bundle(url: url)
    {
        return bundle
    }
    return .module
}()

private func localizedTemplate(for key: String) -> String {
    let preferred =
        LanguageManager.languageOverride
        ?? LanguageManager.activeDefaults.string(forKey: LanguageManager.appStorageKey)
        ?? ""
    if !preferred.isEmpty {
        // SwiftPM lowercases lproj directory names on case-insensitive filesystems,
        // so try the IANA-style code (zh-Hans) first then the lowercased form.
        let candidates = preferred == preferred.lowercased() ? [preferred] : [preferred, preferred.lowercased()]
        for candidate in candidates {
            // `L()` runs inside every SwiftUI body, so resolving the lproj
            // bundle per call (path lookup + fresh Bundle + strings parse)
            // shows up on hot views. Cache per language code instead; the
            // set of bundles never changes at runtime.
            if let bundle = LanguageManager.cachedBundle(for: candidate, in: resourceBundle) {
                let value = bundle.localizedString(forKey: key, value: key, table: nil)
                if value != key { return value }
            }
        }
    }
    return NSLocalizedString(key, tableName: nil, bundle: resourceBundle, value: key, comment: "")
}

enum LanguageManager {
    static let appStorageKey = "shipnotes.uiLanguage"

    /// Backing store for the UI-language preference. Defaults to `.standard`
    /// for production; tests override this with an ephemeral suite so they
    /// don't pollute (or depend on) the user's real defaults.
    ///
    /// Thread-safety: UserDefaults reads are inherently thread-safe. The mutable
    /// `activeDefaults` var is written ONLY at app launch (applyPersistedLanguageAtLaunch)
    /// or in test setUp. Do not write from any other path.
    nonisolated(unsafe) static var activeDefaults: UserDefaults = .standard

    /// Test-only: a language code (`""` = follow the system) scoped to the
    /// current task, so a test can resolve strings in another language
    /// without changing what `L()` returns for code running concurrently in
    /// other tests.
    @TaskLocal static var languageOverride: String?

    /// lproj bundles resolved for a given language code, so `L()` doesn't
    /// re-resolve the same path on every call. `L()` is reachable from
    /// non-main threads (error descriptions built inside Task.detached), so
    /// the cache is lock-guarded.
    private static let bundleCacheLock = NSLock()
    nonisolated(unsafe) private static var bundleCache: [String: Bundle?] = [:]

    static func cachedBundle(for languageCode: String, in resourceBundle: Bundle) -> Bundle? {
        bundleCacheLock.lock()
        defer { bundleCacheLock.unlock() }
        if let cached = bundleCache[languageCode] { return cached }
        guard let path = resourceBundle.path(forResource: languageCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            bundleCache[languageCode] = nil
            return nil
        }
        bundleCache[languageCode] = bundle
        return bundle
    }

    /// Apply the persisted language to `AppleLanguages` at process start so
    /// system controls (date pickers, NSAlert default buttons) also pick it up.
    static func applyPersistedLanguageAtLaunch() {
        let stored = activeDefaults.string(forKey: appStorageKey) ?? ""
        if stored.isEmpty {
            activeDefaults.removeObject(forKey: "AppleLanguages")
        } else {
            activeDefaults.set([stored], forKey: "AppleLanguages")
        }
    }

    static func setLanguage(_ option: LanguageOption) {
        activeDefaults.set(option.rawValue, forKey: appStorageKey)
        if option.rawValue.isEmpty {
            activeDefaults.removeObject(forKey: "AppleLanguages")
        } else {
            activeDefaults.set([option.rawValue], forKey: "AppleLanguages")
        }
    }

    static var currentOption: LanguageOption {
        let stored = activeDefaults.string(forKey: appStorageKey) ?? ""
        return LanguageOption(rawValue: stored) ?? .system
    }

    @MainActor
    static func promptRestart() {
        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = L("Language change requires a restart.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Quit Now"))
        alert.addButton(withTitle: L("Restart Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
        #endif
    }
}
