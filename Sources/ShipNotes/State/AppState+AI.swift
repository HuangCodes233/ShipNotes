import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    func bumpAICallCount() {
        aiCallCount += 1
        defaults.set(aiCallCount, forKey: SettingsKey.aiCallCount)
    }

    internal static func loadStoredVisionAIProvider(defaults: UserDefaults = .standard) -> AIProvider {
        guard let raw = defaults.string(forKey: SettingsKey.aiVisionProvider),
            let provider = AIProvider(rawValue: raw),
            provider.supportsVisionInput
        else {
            return .none
        }
        return provider
    }

    func resetAICallCount() {
        aiCallCount = 0
        defaults.removeObject(forKey: SettingsKey.aiCallCount)
    }

    func aiBaseURL(for provider: AIProvider, role: AIProfileRole = .text) -> URL {
        let stored =
            defaults.string(forKey: provider.baseURLDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (stored.isEmpty ? nil : URL(string: stored)) ?? provider.defaultBaseURL
    }

    func aiModel(for provider: AIProvider, role: AIProfileRole = .text) -> String {
        let stored =
            defaults.string(forKey: provider.modelDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? provider.defaultModel(for: role) : stored
    }

    func aiAPIFormat(for provider: AIProvider, role: AIProfileRole = .text) -> OpenAIAPIFormat {
        guard provider == .openai,
            let raw = defaults.string(forKey: provider.apiFormatDefaultsKey(for: role)),
            let format = OpenAIAPIFormat(rawValue: raw)
        else { return .chatCompletions }
        return format
    }

    func hasUnsavedAIProfileChanges(
        provider: AIProvider, baseURL: String, model: String, apiFormat: OpenAIAPIFormat,
        apiKeyInput: String, role: AIProfileRole
    ) -> Bool {
        let activeProvider = role == .text ? selectedAIProvider : selectedVisionAIProvider
        return provider != activeProvider
            || !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || baseURL.trimmingCharacters(in: .whitespacesAndNewlines) != storedAIBaseURL(for: provider, role: role)
            || model.trimmingCharacters(in: .whitespacesAndNewlines) != storedAIModel(for: provider, role: role)
            || (provider == .openai && apiFormat != aiAPIFormat(for: provider, role: role))
    }

    /// The raw stored base-URL string (empty if the user hasn't overridden the
    /// default). Used by SettingsView to show what the user typed, not the
    /// resolved value.
    func storedAIBaseURL(for provider: AIProvider, role: AIProfileRole = .text) -> String {
        defaults.string(forKey: provider.baseURLDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The raw stored model string (empty if using the provider default).
    func storedAIModel(for provider: AIProvider, role: AIProfileRole = .text) -> String {
        defaults.string(forKey: provider.modelDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Keychain IO runs detached: a Keychain round-trip (which may prompt for
    /// authorization) must not block the main actor in a Settings interaction.
    @discardableResult
    func reloadAIServiceFromKeychain(
        allowsAuthenticationUI: Bool = true, preferredProvider: AIProvider? = nil
    ) async -> Bool {
        await reloadAIConfiguration(
            role: .text, allowsAuthenticationUI: allowsAuthenticationUI,
            preferredProvider: preferredProvider ?? selectedAIProvider)
    }

    func reloadAIServiceFromKeychainInBackground(allowsAuthenticationUI: Bool) async {
        guard !isSavingAIConfiguration else { return }
        _ = await reloadAIServiceFromKeychain(allowsAuthenticationUI: allowsAuthenticationUI)
    }

    func makeAIService(for provider: AIProvider, cachedKey: String?) -> any AIService {
        let baseURL = aiBaseURL(for: provider)
        let model = aiModel(for: provider)
        switch provider {
        case .anthropic:
            return AnthropicService(
                keychainStore: aiKeychainStore,
                baseURL: baseURL,
                model: model,
                cachedKey: cachedKey
            )
        case .openai:
            return OpenAIService(
                keychainStore: aiKeychainStore,
                baseURL: baseURL,
                model: model,
                apiFormat: aiAPIFormat(for: provider),
                cachedKey: cachedKey
            )
        case .none:
            return UnconfiguredAIService()
        }
    }

    @discardableResult
    func saveAIKey(_ apiKey: String, for provider: AIProvider) async -> Bool {
        await saveAIConfigurationKey(apiKey, for: provider, role: .text)
    }

    func saveAIEndpointConfig(
        baseURL: String, model: String, apiFormat: OpenAIAPIFormat? = nil,
        for provider: AIProvider, role: AIProfileRole = .text
    ) {
        guard provider != .none else { return }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            defaults.removeObject(forKey: provider.baseURLDefaultsKey(for: role))
        } else {
            defaults.set(trimmedURL, forKey: provider.baseURLDefaultsKey(for: role))
        }
        if trimmedModel.isEmpty {
            defaults.removeObject(forKey: provider.modelDefaultsKey(for: role))
        } else {
            defaults.set(trimmedModel, forKey: provider.modelDefaultsKey(for: role))
        }
        if provider == .openai, let apiFormat {
            defaults.set(apiFormat.rawValue, forKey: provider.apiFormatDefaultsKey(for: role))
        }
    }

    /// Settings saves endpoint choices and credentials as one applied profile.
    /// Endpoint choices commit only after the matching Keychain operation
    /// succeeds, so stale/failed saves never become another save's baseline.
    @discardableResult
    func saveAIProfileConfiguration(
        baseURL: String, model: String, apiFormat: OpenAIAPIFormat,
        apiKeyInput: String, for provider: AIProvider, role: AIProfileRole
    ) async -> Bool {
        guard provider != .none, role != .vision || provider.supportsVisionInput else { return false }
        let requestID = beginAIConfigurationRequest(role: role)
        defer { endAIConfigurationRequest(requestID, role: role) }
        do {
            let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let configuration: StoredAIConfiguration?
            if key.isEmpty {
                let operation = aiConfigurationPersistence.load(
                    role: role, preferredProvider: provider, allowsAuthenticationUI: true)
                configuration = try await operation.value
            } else {
                let operation = aiConfigurationPersistence.save(key, provider: provider, role: role)
                try await operation.value
                configuration = StoredAIConfiguration(provider: provider, key: key)
            }
            guard ownsAIConfigurationRequest(requestID, role: role) else { return false }
            guard !Task.isCancelled else { return false }
            guard configuration?.provider == provider else {
                handleError(AIServiceError.missingAPIKey)
                return false
            }
            saveAIEndpointConfig(baseURL: baseURL, model: model, apiFormat: apiFormat, for: provider, role: role)
            applyAIConfiguration(configuration, role: role)
            clearLastErrorPreservingWorkspaceDraftError()
            return true
        } catch {
            guard ownsAIConfigurationRequest(requestID, role: role) else { return false }
            if !Task.isCancelled { handleError(error) }
            return false
        }
    }

    @discardableResult
    func removeAIKey(for provider: AIProvider) async -> Bool {
        await removeAIConfigurationKey(for: provider, role: .text)
    }

    @discardableResult
    func reloadVisionAIServiceFromKeychain(
        allowsAuthenticationUI: Bool = true, preferredProvider: AIProvider? = nil
    ) async -> Bool {
        await reloadAIConfiguration(
            role: .vision, allowsAuthenticationUI: allowsAuthenticationUI,
            preferredProvider: preferredProvider ?? selectedVisionAIProvider)
    }

    func reloadVisionAIServiceFromKeychainInBackground(allowsAuthenticationUI: Bool) async {
        guard !isSavingVisionAIConfiguration else { return }
        _ = await reloadVisionAIServiceFromKeychain(allowsAuthenticationUI: allowsAuthenticationUI)
    }

    func makeVisionAIService(for provider: AIProvider, cachedKey: String?) -> any ScreenshotVisionAIService {
        let baseURL = aiBaseURL(for: provider, role: .vision)
        let model = aiModel(for: provider, role: .vision)
        switch provider {
        case .anthropic:
            return AnthropicScreenshotVisionAIService(
                keychainStore: aiKeychainStore,
                baseURL: baseURL,
                model: model,
                cachedKey: cachedKey
            )
        case .openai:
            return OpenAIScreenshotVisionAIService(
                keychainStore: aiKeychainStore,
                baseURL: baseURL,
                model: model,
                apiFormat: aiAPIFormat(for: provider, role: .vision),
                cachedKey: cachedKey
            )
        case .none:
            return UnconfiguredScreenshotVisionAIService()
        }
    }

    @discardableResult
    func saveVisionAIKey(_ apiKey: String, for provider: AIProvider) async -> Bool {
        await saveAIConfigurationKey(apiKey, for: provider, role: .vision)
    }

    @discardableResult
    func removeVisionAIKey(for provider: AIProvider) async -> Bool {
        await removeAIConfigurationKey(for: provider, role: .vision)
    }

    private func beginAIConfigurationRequest(role: AIProfileRole) -> UInt64 {
        aiConfigurationRequestSequence &+= 1
        switch role {
        case .text:
            aiTextConfigurationRequestID = aiConfigurationRequestSequence
            isSavingAIConfiguration = true
        case .vision:
            aiVisionConfigurationRequestID = aiConfigurationRequestSequence
            isSavingVisionAIConfiguration = true
        }
        return aiConfigurationRequestSequence
    }

    private func ownsAIConfigurationRequest(_ requestID: UInt64, role: AIProfileRole) -> Bool {
        requestID == (role == .text ? aiTextConfigurationRequestID : aiVisionConfigurationRequestID)
    }

    private func endAIConfigurationRequest(_ requestID: UInt64, role: AIProfileRole) {
        guard ownsAIConfigurationRequest(requestID, role: role) else { return }
        if role == .text { isSavingAIConfiguration = false } else { isSavingVisionAIConfiguration = false }
    }

    private func applyAIConfiguration(_ configuration: StoredAIConfiguration?, role: AIProfileRole) {
        switch role {
        case .text:
            selectedAIProvider = configuration?.provider ?? .none
            aiService =
                configuration.map { makeAIService(for: $0.provider, cachedKey: $0.key) }
                ?? UnconfiguredAIService()
        case .vision:
            if let configuration {
                selectedVisionAIProvider = configuration.provider
                defaults.set(configuration.provider.rawValue, forKey: SettingsKey.aiVisionProvider)
                visionAIService = makeVisionAIService(for: configuration.provider, cachedKey: configuration.key)
            } else {
                selectedVisionAIProvider = Self.loadStoredVisionAIProvider(defaults: defaults)
                visionAIService = UnconfiguredScreenshotVisionAIService()
            }
        }
    }

    private func reloadAIConfiguration(
        role: AIProfileRole, allowsAuthenticationUI: Bool, preferredProvider: AIProvider?
    ) async -> Bool {
        let requestID = beginAIConfigurationRequest(role: role)
        defer { endAIConfigurationRequest(requestID, role: role) }
        // Enqueue before suspending so this read cannot overtake an earlier
        // write, or publish its cached key after a newer save/removal.
        let operation = aiConfigurationPersistence.load(
            role: role, preferredProvider: preferredProvider, allowsAuthenticationUI: allowsAuthenticationUI)
        do {
            let configuration = try await operation.value
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            applyAIConfiguration(configuration, role: role)
            return configuration != nil
        } catch {
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            handleError(error)
            return false
        }
    }

    private func saveAIConfigurationKey(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) async -> Bool {
        guard provider != .none, role != .vision || provider.supportsVisionInput else { return false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            handleError(AIServiceError.missingAPIKey)
            return false
        }
        let requestID = beginAIConfigurationRequest(role: role)
        defer { endAIConfigurationRequest(requestID, role: role) }
        let operation = aiConfigurationPersistence.save(key, provider: provider, role: role)
        do {
            try await operation.value
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            applyAIConfiguration(StoredAIConfiguration(provider: provider, key: key), role: role)
            clearLastErrorPreservingWorkspaceDraftError()
            return true
        } catch {
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            handleError(error)
            return false
        }
    }

    private func removeAIConfigurationKey(for provider: AIProvider, role: AIProfileRole) async -> Bool {
        guard provider != .none else { return false }
        let requestID = beginAIConfigurationRequest(role: role)
        defer { endAIConfigurationRequest(requestID, role: role) }
        let preferredProvider = role == .text ? selectedAIProvider : selectedVisionAIProvider
        let operation = aiConfigurationPersistence.removeAndLoad(
            provider: provider, role: role, preferredProvider: preferredProvider)
        do {
            let configuration = try await operation.value
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            applyAIConfiguration(configuration, role: role)
            clearLastErrorPreservingWorkspaceDraftError()
            return true
        } catch {
            guard !Task.isCancelled, ownsAIConfigurationRequest(requestID, role: role) else { return false }
            handleError(error)
            return false
        }
    }

    @discardableResult
    func testAIConnection() async -> Bool {
        guard !isAIRunning, !isSavingAIConfiguration else { return false }
        let service = aiService
        guard service.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return false
        }
        isAIRunning = true
        defer { isAIRunning = false }
        do {
            _ = try await service.translate(text: "Hello.", fromLocale: "en-US", toLocale: "ja", glossary: [:])
            bumpAICallCount()
            // Settings shows its own success message; `connectionStatus`
            // describes the App Store Connect connection.
            clearLastErrorPreservingWorkspaceDraftError()
            return true
        } catch {
            handleError(error)
            return false
        }
    }

    @discardableResult
    func testVisionAIConnection() async -> Bool {
        guard !isAIRunning, !isSavingVisionAIConfiguration else { return false }
        let service = visionAIService
        guard service.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return false
        }
        isAIRunning = true
        defer { isAIRunning = false }
        do {
            try await service.testConnection()
            bumpAICallCount()
            clearLastErrorPreservingWorkspaceDraftError()
            return true
        } catch {
            handleError(error)
            return false
        }
    }

    func askAIToReparsePendingImport() {
        guard let url = pendingImportURL else { return }
        askAIToParse(url: url)
    }

    nonisolated internal static func readTextForAI(at url: URL) async throws -> String {
        return try await Task.detached {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                throw ReleaseNotesParserError.folderUnreadable(url)
            }
            if !isDir.boolValue {
                return try String(contentsOf: url, encoding: .utf8)
            }

            let supportedExts: Set<String> = ["md", "markdown", "txt", "yaml", "yml", "json"]
            let maxPayload = 400_000
            let maxFiles = 80
            var pieces: [String] = []
            var totalSize = 0
            var skipped = 0

            let rootPath = url.standardizedFileURL.path
            var candidates: [(url: URL, score: Int)] = []

            func normalized(_ value: String) -> String {
                value.lowercased().filter { $0.isLetter || $0.isNumber }
            }

            func score(_ fileURL: URL) -> Int {
                let path = fileURL.standardizedFileURL.path.lowercased()
                let basename = normalized((fileURL.lastPathComponent as NSString).deletingPathExtension)
                var score = 0
                if path.contains("/appstore/") { score += 80 }
                if path.contains("/metadata/") { score += 70 }
                if basename == "changelog" { score += 65 }
                if basename.contains("releasenotes") { score += 65 }
                if basename.contains("whatsnew") { score += 55 }
                if basename.contains("versionhistory") { score += 45 }
                if basename.contains("appstore") { score += 35 }
                if basename.contains("metadata") { score += 30 }
                if basename.contains("release") { score += 20 }
                return score
            }

            func walk(_ folder: URL, depth: Int) {
                guard depth <= 5, candidates.count < maxFiles * 4 else { return }
                let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                for child in entries.sorted(by: { $0.path < $1.path }) {
                    var childIsDir: ObjCBool = false
                    fm.fileExists(atPath: child.path, isDirectory: &childIsDir)
                    if FileScannerUtils.shouldSkip(child, isDirectory: childIsDir.boolValue) { continue }
                    if childIsDir.boolValue {
                        walk(child, depth: depth + 1)
                        continue
                    }
                    let ext = child.pathExtension.lowercased()
                    guard supportedExts.contains(ext) else { continue }
                    candidates.append((child, score(child)))
                }
            }

            walk(url, depth: 0)

            let selected =
                candidates
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    if lhs.url.path.count != rhs.url.path.count { return lhs.url.path.count < rhs.url.path.count }
                    return lhs.url.path < rhs.url.path
                }
                .prefix(maxFiles)

            for fileURL in selected.map(\.url) {
                let ext = fileURL.pathExtension.lowercased()
                guard supportedExts.contains(ext) else { continue }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let standardizedPath = fileURL.standardizedFileURL.path
                let relativePath: String
                if standardizedPath.hasPrefix(rootPath) {
                    let rawRelative = String(standardizedPath.dropFirst(rootPath.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    relativePath = rawRelative.isEmpty ? fileURL.lastPathComponent : rawRelative
                } else {
                    relativePath = fileURL.lastPathComponent
                }
                let header = "\n\n=== FILE: \(relativePath) ===\n\n"
                let chunkSize = header.count + content.count
                if totalSize + chunkSize > maxPayload {
                    skipped += 1
                    continue
                }
                pieces.append(header + content)
                totalSize += chunkSize
            }
            if skipped > 0 {
                pieces.append("\n\n[\(skipped) more files omitted due to size limit]")
            }
            if pieces.isEmpty {
                throw ReleaseNotesParserError.noLocaleFilesFound(url)
            }
            return pieces.joined()
        }.value
    }
}
