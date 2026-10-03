import Foundation
import Testing

/// Poll `condition` every `interval` nanoseconds until it returns true or
/// `timeout` nanoseconds elapse. Returns true if the condition was met.
///
/// Prefer this over a raw `for _ in 0..<N` sleep loop so failures surface as
/// a single timed-out expectation instead of a silent miss.
///
/// Usage in tests:
/// ```swift
/// #expect(await waitUntil { state.isSyncing == false })
/// ```
@MainActor
func waitUntil(
    timeout: UInt64 = 3_000_000_000,
    interval: UInt64 = 20_000_000,
    condition: () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeout
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: interval)
    }
    return condition()
}

/// Create an ephemeral `UserDefaults` suite for tests so they never read from
/// or write to the user's real `.standard` defaults. Each call returns a fresh,
/// empty suite.
@MainActor
func makeTestDefaults() -> UserDefaults {
    let suiteName = "shipnotes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Expected value for assertions that compare against a localized string the
/// production code produced earlier. Evaluating `L()` at assert time races
/// with LocalizationTests flipping the process-wide UI language (suites run
/// in parallel), which made these comparisons flaky — pinning the expected
/// text to English removes the shared-state dependency.
func expectedLocalized(_ key: String, _ arguments: any CVarArg...) -> String {
    let template = englishTemplate(for: key)
    return arguments.isEmpty ? template : String(format: template, arguments)
}

private func englishTemplate(for key: String) -> String {
    // Resolve the en.lproj bundle straight from the ShipNotes module bundle.
    // `Bundle.module` is inaccessible from the test target, so locate the
    // resource bundle the same way Localization.swift does at runtime.
    let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "ShipNotes_ShipNotes", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        // Fallback for test runs: derive the bundle from this file's path
        // (…/ShipNotes.app/Contents/Resources/… or .build/…/ShipNotes_ShipNotes.bundle).
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            let candidate = url.appending(path: "ShipNotes_ShipNotes.bundle")
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return Bundle.main
    }()
    guard let path = resourceBundle.path(forResource: "en", ofType: "lproj"),
        let bundle = Bundle(path: path)
    else {
        return key
    }
    let value = bundle.localizedString(forKey: key, value: key, table: nil)
    return value == key ? key : value
}
