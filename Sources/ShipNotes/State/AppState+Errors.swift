import Foundation

@MainActor
extension AppState {
    func handleError(_ error: Error) {
        if Self.isCancellation(error) { return }
        let category = Self.category(for: error)
        self.lastError = AppError(
            error.localizedDescription,
            category: category,
            recoverySuggestion: Self.recoverySuggestion(for: category),
            isRetryable: category == .network || category == .appStoreConnect
        )
    }

    /// Pure error classification, separate from `handleError` so off-main-actor
    /// code (parallel sync workers) can classify a caught error and hand back
    /// the category with the message for the main actor to render.
    nonisolated static func category(for error: Error) -> AppError.Category {
        switch error {
        case is URLError:
            return .network
        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            return .network
        case let nsError as NSError where nsError.domain == NSCocoaErrorDomain:
            return .fileIO
        case let aiError as AIServiceError:
            // Network-layer failures from the AI provider are connectivity
            // issues, not AI-specific rejections.
            if case .networkError = aiError {
                return .network
            } else {
                return .ai
            }
        case let asc as AppStoreConnectClientError:
            switch asc {
            case .connectionTimedOut, .networkError:
                return .network
            default:
                return .appStoreConnect
            }
        case is AppStoreConnectCredentialError:
            return .auth
        case is AppleAdsCredentialError:
            return .auth
        case let ads as AppleAdsClientError:
            switch ads {
            case .connectionTimedOut, .networkError:
                return .network
            case .unauthorized, .missingAdAccount:
                return .auth
            default:
                return .unknown
            }
        default:
            return .unknown
        }
    }

    nonisolated static func recoverySuggestion(for category: AppError.Category) -> String? {
        switch category {
        case .network:
            return L("Check your internet connection and try again.")
        case .auth:
            return L("Open Settings and re-enter your App Store Connect credentials.")
        case .ai:
            return L("Open Settings -> AI to verify your API key and provider.")
        case .appStoreConnect:
            return nil
        case .validation, .fileIO, .unknown:
            return nil
        }
    }
    func dismissError() {
        workspaceDraftConflictError = nil
        lastError = nil
    }

    /// Convenience setter for user-facing / validation messages that are not a
    /// thrown `Error`. Prefer `handleError(_:)` for caught errors so category
    /// and retryability stay accurate.
    func setError(
        _ message: String,
        category: AppError.Category = .validation,
        isRetryable: Bool = false
    ) {
        lastError = AppError(message, category: category, isRetryable: isRetryable)
    }
}
