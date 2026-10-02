import Foundation

/// Structured error displayed to the user via the top-level ErrorBanner.
/// Conforms to `ExpressibleByStringLiteral` so existing `lastError = "some string"`
/// assignments compile without modification during the incremental migration.
/// Prefer `AppState.handleError(_:)` for thrown errors and `setError(_:category:)`
/// for validation / user-facing messages.
struct AppError: Identifiable, Equatable, LocalizedError, ExpressibleByStringLiteral {
    let id: UUID
    var category: Category
    var message: String
    var recoverySuggestion: String?
    var isRetryable: Bool

    enum Category: Equatable, Sendable {
        case network
        case auth
        case validation
        case ai
        case appStoreConnect
        case fileIO
        case unknown
    }

    init(
        _ message: String,
        category: Category = .unknown,
        recoverySuggestion: String? = nil,
        isRetryable: Bool = false
    ) {
        self.id = UUID()
        self.category = category
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.isRetryable = isRetryable
    }

    // ExpressibleByStringLiteral — allows `lastError = "plain string"` to compile.
    init(stringLiteral value: String) {
        self.init(value)
    }

    var errorDescription: String? { message }

    /// Two AppErrors are equal if they carry the same message (ignoring id).
    /// This keeps `#expect(state.lastError == "some text")`-style comparisons
    /// working after migration when both sides are AppError literals.
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.message == rhs.message
            && lhs.category == rhs.category
    }
}
