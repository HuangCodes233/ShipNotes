import Foundation

@MainActor
extension AppState {
    func handleError(_ error: Error) {
        if Self.isCancellation(error) { return }
        let category: AppError.Category
        switch error {
        case is URLError:
            category = .network
        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            category = .network
        case let nsError as NSError where nsError.domain == NSCocoaErrorDomain:
            category = .fileIO
        case let aiError as AIServiceError:
            // Network-layer failures from the AI provider are connectivity
            // issues, not AI-specific rejections.
            if case .networkError = aiError {
                category = .network
            } else {
                category = .ai
            }
        case let asc as AppStoreConnectClientError:
            switch asc {
            case .connectionTimedOut, .networkError:
                category = .network
            default:
                category = .appStoreConnect
            }
        case is AppStoreConnectCredentialError:
            category = .auth
        case is AppleAdsCredentialError:
            category = .auth
        case let ads as AppleAdsClientError:
            switch ads {
            case .connectionTimedOut, .networkError:
                category = .network
            case .unauthorized, .missingAdAccount:
                category = .auth
            default:
                category = .unknown
            }
        default:
            category = .unknown
        }
        self.lastError = AppError(
            error.localizedDescription,
            category: category,
            recoverySuggestion: Self.recoverySuggestion(for: category),
            isRetryable: category == .network || category == .appStoreConnect
        )
    }

    private static func recoverySuggestion(for category: AppError.Category) -> String? {
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
    func dismissError() { lastError = nil }

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
