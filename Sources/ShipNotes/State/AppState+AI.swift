import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    internal func bumpAICallCount() {
        aiCallCount += 1
        defaults.set(aiCallCount, forKey: SettingsKey.aiCallCount)
    }

    internal static func loadStoredVisionAIProvider(defaults: UserDefaults = .standard) -> AIProvider {
        guard let raw = defaults.string(forKey: SettingsKey.aiVisionProvider),
              let provider = AIProvider(rawValue: raw),
              provider.supportsVisionInput else {
            return .none
        }
        return provider
    }

    func resetAICallCount() {
        aiCallCount = 0
        defaults.removeObject(forKey: SettingsKey.aiCallCount)
    }

    func aiBaseURL(for provider: AIProvider, role: AIProfileRole = .text) -> URL {
        let stored = defaults.string(forKey: provider.baseURLDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (stored.isEmpty ? nil : URL(string: stored)) ?? provider.defaultBaseURL
    }

    func aiModel(for provider: AIProvider, role: AIProfileRole = .text) -> String {
        let stored = defaults.string(forKey: provider.modelDefaultsKey(for: role))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? provider.defaultModel(for: role) : stored
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

    func reloadAIServiceFromKeychain(allowsAuthenticationUI: Bool = true) {
        for provider in AIProvider.allCases where provider != .none {
            let key = try? (allowsAuthenticationUI
                ? aiKeychainStore.load(for: provider)
                : aiKeychainStore.loadWithoutPrompt(for: provider))
            if let key, !key.isEmpty {
                selectedAIProvider = provider
                aiService = makeAIService(for: provider, cachedKey: key)
                return
            }
        }
        selectedAIProvider = .none
        aiService = UnconfiguredAIService()
    }

    internal func reloadAIServiceFromKeychainInBackground(allowsAuthenticationUI: Bool) async {
        let providerBeforeLoad = selectedAIProvider
        let store = aiKeychainStore
        let candidate = await Task.detached(priority: .utility) { () -> (AIProvider, String)? in
            for provider in AIProvider.allCases where provider != .none {
                let key = try? (allowsAuthenticationUI
                    ? store.load(for: provider)
                    : store.loadWithoutPrompt(for: provider))
                if let key, !key.isEmpty {
                    return (provider, key)
                }
            }
            return nil
        }.value

        guard selectedAIProvider == providerBeforeLoad else {
            return
        }
        if let (provider, key) = candidate {
            selectedAIProvider = provider
            aiService = makeAIService(for: provider, cachedKey: key)
        } else {
            selectedAIProvider = .none
            aiService = UnconfiguredAIService()
        }
    }

    internal func makeAIService(for provider: AIProvider, cachedKey: String?) -> any AIService {
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
                cachedKey: cachedKey
            )
        case .none:
            return UnconfiguredAIService()
        }
    }

    func saveAIKey(_ apiKey: String, for provider: AIProvider) {
        guard provider != .none else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleError(AIServiceError.missingAPIKey)
            return
        }
        do {
            try aiKeychainStore.save(trimmed, for: provider)
            // Construct the service directly with the key in hand — don't rely
            // on an immediate Keychain re-read (flaky on ad-hoc-signed runs).
            selectedAIProvider = provider
            aiService = makeAIService(for: provider, cachedKey: trimmed)
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func saveAIEndpointConfig(baseURL: String, model: String, for provider: AIProvider, role: AIProfileRole = .text) {
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
    }

    func removeAIKey(for provider: AIProvider) {
        do {
            try aiKeychainStore.delete(for: provider)
            reloadAIServiceFromKeychain()
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func reloadVisionAIServiceFromKeychain(allowsAuthenticationUI: Bool = true) {
        for provider in AIProvider.allCases where provider.supportsVisionInput {
            let key = try? (allowsAuthenticationUI
                ? aiKeychainStore.load(for: provider, role: .vision)
                : aiKeychainStore.loadWithoutPrompt(for: provider, role: .vision))
            if let key, !key.isEmpty {
                selectedVisionAIProvider = provider
                defaults.set(provider.rawValue, forKey: SettingsKey.aiVisionProvider)
                visionAIService = makeVisionAIService(for: provider, cachedKey: key)
                return
            }
        }
        selectedVisionAIProvider = Self.loadStoredVisionAIProvider(defaults: defaults)
        visionAIService = UnconfiguredScreenshotVisionAIService()
    }

    internal func reloadVisionAIServiceFromKeychainInBackground(allowsAuthenticationUI: Bool) async {
        let providerBeforeLoad = selectedVisionAIProvider
        let store = aiKeychainStore
        let candidate = await Task.detached(priority: .utility) { () -> (AIProvider, String)? in
            for provider in AIProvider.allCases where provider.supportsVisionInput {
                let key = try? (allowsAuthenticationUI
                    ? store.load(for: provider, role: .vision)
                    : store.loadWithoutPrompt(for: provider, role: .vision))
                if let key, !key.isEmpty {
                    return (provider, key)
                }
            }
            return nil
        }.value

        guard selectedVisionAIProvider == providerBeforeLoad else {
            return
        }
        if let (provider, key) = candidate {
            selectedVisionAIProvider = provider
            defaults.set(provider.rawValue, forKey: SettingsKey.aiVisionProvider)
            visionAIService = makeVisionAIService(for: provider, cachedKey: key)
        } else {
            selectedVisionAIProvider = Self.loadStoredVisionAIProvider(defaults: defaults)
            visionAIService = UnconfiguredScreenshotVisionAIService()
        }
    }

    internal func makeVisionAIService(for provider: AIProvider, cachedKey: String?) -> any ScreenshotVisionAIService {
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
                cachedKey: cachedKey
            )
        case .none:
            return UnconfiguredScreenshotVisionAIService()
        }
    }

    func saveVisionAIKey(_ apiKey: String, for provider: AIProvider) {
        guard provider.supportsVisionInput else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleError(AIServiceError.missingAPIKey)
            return
        }
        do {
            try aiKeychainStore.save(trimmed, for: provider, role: .vision)
            selectedVisionAIProvider = provider
            defaults.set(provider.rawValue, forKey: SettingsKey.aiVisionProvider)
            visionAIService = makeVisionAIService(for: provider, cachedKey: trimmed)
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func removeVisionAIKey(for provider: AIProvider) {
        do {
            try aiKeychainStore.delete(for: provider, role: .vision)
            if selectedVisionAIProvider == provider {
                visionAIService = UnconfiguredScreenshotVisionAIService()
            }
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func testAIConnection() async {
        guard aiService.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return
        }
        isAIRunning = true
        defer { isAIRunning = false }
        do {
            _ = try await aiService.translate(text: "Hello.", fromLocale: "en-US", toLocale: "ja", glossary: [:])
            bumpAICallCount()
            // Settings shows its own success message; `connectionStatus`
            // describes the App Store Connect connection.
            lastError = nil
        } catch {
            handleError(error)
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

        let selected = candidates
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
