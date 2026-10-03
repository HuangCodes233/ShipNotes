import OSLog

extension Logger {
    /// Network requests to App Store Connect and AI providers.
    static let network = Logger(subsystem: "org.shipnotes.app", category: "network")
    /// AI provider interactions (parse, translate, optimize).
    static let ai = Logger(subsystem: "org.shipnotes.app", category: "ai")
    /// Sync operations (dry run, live sync, store copy sync).
    static let sync = Logger(subsystem: "org.shipnotes.app", category: "sync")
    /// File scanning and parsing (release notes, screenshots, store copy).
    static let scanner = Logger(subsystem: "org.shipnotes.app", category: "scanner")
}
