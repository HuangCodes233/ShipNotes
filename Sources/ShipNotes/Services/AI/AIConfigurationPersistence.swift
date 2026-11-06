import Foundation

struct StoredAIConfiguration: Sendable {
    let provider: AIProvider
    let key: String
}

/// Enqueue synchronously on the model's actor before its first suspension.
/// The detached operations then wait on the previous operation, so reads,
/// saves and removals reach Keychain in user-intent order without blocking UI.
/// Cancelling a waiter does not abandon an already-enqueued removal.
@MainActor
final class AIConfigurationPersistence {
    private let store: any AIKeychainStoring
    private var tail: Task<Void, Never>?

    init(store: any AIKeychainStoring) { self.store = store }

    func save(_ key: String, provider: AIProvider, role: AIProfileRole) -> Task<Void, Error> {
        enqueue { store in try store.save(key, for: provider, role: role) }
    }

    func load(
        role: AIProfileRole, preferredProvider: AIProvider?, allowsAuthenticationUI: Bool
    ) -> Task<StoredAIConfiguration?, Error> {
        enqueue { store in
            Self.loadFirstConfigured(
                store: store, role: role, preferredProvider: preferredProvider,
                allowsAuthenticationUI: allowsAuthenticationUI)
        }
    }

    func removeAndLoad(
        provider: AIProvider, role: AIProfileRole, preferredProvider: AIProvider?
    ) -> Task<StoredAIConfiguration?, Error> {
        enqueue { store in
            try store.delete(for: provider, role: role)
            return Self.loadFirstConfigured(
                store: store, role: role, preferredProvider: preferredProvider,
                allowsAuthenticationUI: true)
        }
    }

    private func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable (any AIKeychainStoring) throws -> Value
    ) -> Task<Value, Error> {
        let previous = tail
        let store = store
        let result = Task.detached(priority: .userInitiated) {
            await previous?.value
            return try operation(store)
        }
        // Keep the ordering barrier even when an individual operation fails.
        tail = Task.detached { _ = try? await result.value }
        return result
    }

    nonisolated private static func loadFirstConfigured(
        store: any AIKeychainStoring, role: AIProfileRole,
        preferredProvider: AIProvider?, allowsAuthenticationUI: Bool
    ) -> StoredAIConfiguration? {
        var providers = AIProvider.allCases.filter { role == .vision ? $0.supportsVisionInput : $0 != .none }
        if let preferredProvider, providers.contains(preferredProvider) {
            providers.removeAll { $0 == preferredProvider }
            providers.insert(preferredProvider, at: 0)
        }
        for provider in providers {
            let key =
                try?
                (allowsAuthenticationUI
                ? store.load(for: provider, role: role)
                : store.loadWithoutPrompt(for: provider, role: role))
            if let key, !key.isEmpty { return StoredAIConfiguration(provider: provider, key: key) }
        }
        return nil
    }
}
