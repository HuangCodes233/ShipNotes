import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

private func captureAsyncResult<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
) async -> Result<Value, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

@MainActor
extension AppState {
    /// Returns whether the version was created. Sheets use the result instead
    /// of `lastError`, which can hold an unrelated message from earlier.
    @discardableResult
    func createVersion(versionString: String, platform: String? = nil) async -> Bool {
        guard let appId = selectedAppId else {
            setError(L("Select an app first."))
            return false
        }
        let trimmedVersion = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else {
            setError(L("Version string cannot be empty."))
            return false
        }

        // Default platform: same as the currently-selected version's platform,
        // or the first existing version's platform, or IOS as a last resort.
        let resolvedPlatform: String = platform
            ?? selectedVersion.flatMap { Self.apiPlatformValue(from: $0.platform) }
            ?? (versionsByApp[appId]?.first.flatMap { Self.apiPlatformValue(from: $0.platform) })
            ?? "IOS"

        guard let service = appStoreService else {
            setError(L("Connect App Store Connect before creating a version."))
            return false
        }
        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let newVersion = try await service.createVersion(
                appId: appId,
                versionString: trimmedVersion,
                platform: resolvedPlatform
            )
            let versions = try await service.fetchVersions(appId: appId)
            versionsByApp[appId] = versions
            let chosenId = versions.first { $0.id == newVersion.id }?.id
                ?? versions.first { $0.versionString == newVersion.versionString }?.id
                ?? newVersion.id
            // Sample data still uses the mock note loader so first-run drafts
            // stay visible; live accounts fetch remote localizations.
            if isUsingMockData {
                selectMockVersion(chosenId)
            } else {
                await selectLiveVersion(chosenId, resetSource: true)
            }
            lastError = nil
            return true
        } catch {
            handleError(error)
            return false
        }
    }

    internal static func apiPlatformValue(from display: String) -> String? {
        switch display.lowercased() {
        case "ios", "ipados": return "IOS"
        case "macos": return "MAC_OS"
        case "tvos": return "TV_OS"
        case "visionos", "xros": return "VISION_OS"
        default: return nil
        }
    }

    /// Returns whether the version is now submitted. The sheet dismisses on
    /// this result — `lastError` alone can't tell "submitted" apart from
    /// "stopped before submitting without setting an error".
    @discardableResult
    func submitSelectedVersionForReview(releaseType: ReleaseType?) async -> Bool {
        guard let service = appStoreService,
              let appId = selectedAppId,
              let version = selectedVersion else {
            // Mock mode (or nothing selected): silently doing nothing would
            // look like a broken button, so surface why the no-op happened.
            if selectedVersion != nil {
                setError(L("Submitting for review requires a live App Store Connect connection. Mock data is read-only."), category: .validation)
            }
            return false
        }

        isSubmittingForReview = true
        defer { isSubmittingForReview = false }
        // Any message now in `lastError` predates this attempt.
        lastError = nil

        // Step 0: Auto-sync any locale that's edited locally but not yet
        // pushed to App Store Connect. Without this, "edit then directly hit
        // Submit" would send the OLD release notes to Apple - easy footgun.
        let pendingLocales = localeNotes
            .filter { $0.status == .ready || $0.status == .needsReview }
            .map(\.locale)
        if !pendingLocales.isEmpty {
            let ok = await syncLiveLocales(pendingLocales)
            // Release-note sync marks failed rows but leaves the banner alone.
            guard ok else {
                if lastError == nil {
                    setError(
                        L("Some release notes could not be synced to App Store Connect. Fix the failed locales, then submit again."),
                        category: .appStoreConnect,
                        isRetryable: true
                    )
                }
                return false
            }
        }

        // Step 0b: Same for store copy (description/keywords/etc). It syncs
        // separately from release notes, so an edited-but-unsynced store copy
        // would otherwise be submitted with its old values.
        let pendingStoreCopy = storeCopyLocales
            .filter { $0.status == .ready || $0.status == .needsReview }
            .map(\.locale)
        if !pendingStoreCopy.isEmpty {
            let ok = await syncLiveStoreCopyLocales(pendingStoreCopy)
            guard ok else {
                if lastError == nil {
                    setError(
                        L("Some store copy could not be synced to App Store Connect. Fix the failed locales, then submit again."),
                        category: .appStoreConnect,
                        isRetryable: true
                    )
                }
                return false
            }
        }

        do {
            if let releaseType {
                try await service.updateVersion(versionId: version.id, releaseType: releaseType.rawValue)
            }
            let platform = Self.apiPlatformValue(from: version.platform) ?? "IOS"
            _ = try await service.submitForReview(appId: appId, versionId: version.id, platform: platform)
            // Refresh versions so the picker shows the new state ("WAITING_FOR_REVIEW").
            let refreshed = try await service.fetchVersions(appId: appId)
            versionsByApp[appId] = refreshed
            lastError = nil
            if isAppleAdsConfigured {
                offerPromoteAfterSubmit = true
            }
            return true
        } catch {
            if await recoverSubmittedVersionState(service: service, appId: appId, versionId: version.id) {
                lastError = nil
                if isAppleAdsConfigured {
                    offerPromoteAfterSubmit = true
                }
                return true
            }
            handleError(error)
            return false
        }
    }

    internal func recoverSubmittedVersionState(
        service: AppStoreConnectServicing,
        appId: String,
        versionId: String
    ) async -> Bool {
        do {
            let refreshed = try await service.fetchVersions(appId: appId)
            versionsByApp[appId] = refreshed
            return refreshed.first { $0.id == versionId }?.appStoreState.isSubmittedForReview == true
        } catch {
            return false
        }
    }

    func loadBuildsForSelectedVersion() async {
        guard let service = appStoreService,
              let appId = selectedAppId,
              let version = selectedVersion else { return }
        let versionId = version.id

        isLoadingBuilds = true
        defer { isLoadingBuilds = false }

        // Two unstructured tasks, not `async let`: async-let children belong
        // to an implicit TaskGroup, and the macOS 27.2 beta runtime crashed
        // in TaskGroup::offer when such a group tore down mid-flight (see
        // mapConcurrently). Each task captures its own error; results are
        // applied only when both finish.
        let buildsTask = Task { await captureAsyncResult {
            try await service.fetchBuilds(appId: appId, marketingVersion: version.versionString)
        } }
        let attachedTask = Task { await captureAsyncResult {
            try await service.fetchAttachedBuild(versionId: versionId)
        } }
        let (builds, attached) = (await buildsTask.value, await attachedTask.value)

        switch (builds, attached) {
        case let (.success(fetchedBuilds), .success(attachedBuild)):
            buildsByVersion[versionId] = fetchedBuilds
            if let attachedBuild {
                attachedBuildByVersion[versionId] = attachedBuild
            } else {
                attachedBuildByVersion.removeValue(forKey: versionId)
            }
            lastError = nil
        case let (.failure(error), _):
            handleError(error)
        case let (_, .failure(error)):
            handleError(error)
        }
    }

    /// Refreshes the two independent sources needed by the new-version sheet:
    /// App Store version records and uploaded prerelease builds. This does not
    /// change the currently selected version or reload the workspace.
    func refreshVersionCreationContext() async {
        guard let service = appStoreService, let appId = selectedAppId else { return }

        let requestID = UUID()
        versionCreationContextRequestID = requestID
        isLoadingVersionCreationContext = true
        versionCreationContextError = nil
        defer {
            if versionCreationContextRequestID == requestID {
                versionCreationContextRequestID = nil
                isLoadingVersionCreationContext = false
            }
        }

        // Unstructured tasks instead of `async let` — same TaskGroup::offer
        // reason as loadBuildsForSelectedVersion above.
        let buildsTask = Task { await captureAsyncResult {
            try await service.fetchAllBuilds(appId: appId)
        } }
        let versionsTask = Task { await captureAsyncResult {
            try await service.fetchVersions(appId: appId)
        } }
        let (builds, versions) = (await buildsTask.value, await versionsTask.value)

        guard versionCreationContextRequestID == requestID, selectedAppId == appId else { return }

        var errors: [String] = []
        switch builds {
        case .success(let builds): uploadedBuildsByApp[appId] = builds
        case .failure(let error): errors.append(error.localizedDescription)
        }
        switch versions {
        case .success(let versions): versionsByApp[appId] = versions
        case .failure(let error): errors.append(error.localizedDescription)
        }

        versionCreationContextError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// Returns whether the build change was accepted by App Store Connect.
    @discardableResult
    func setBuildForSelectedVersion(_ buildId: String?) async -> Bool {
        guard let service = appStoreService, let versionId = selectedVersionId else {
            setError(L("Connect App Store Connect before choosing a build."))
            return false
        }
        isLoadingBuilds = true
        defer { isLoadingBuilds = false }
        do {
            try await service.setBuild(buildId, forVersion: versionId)
            let updated = try? await service.fetchAttachedBuild(versionId: versionId)
            if let updated {
                attachedBuildByVersion[versionId] = updated
            } else {
                attachedBuildByVersion.removeValue(forKey: versionId)
            }
            lastError = nil
            return true
        } catch {
            handleError(error)
            return false
        }
    }

    internal func refreshAttachedBuild(versionId: String, surfaceErrors: Bool) async {
        guard let service = appStoreService else { return }
        isLoadingBuilds = true
        defer { isLoadingBuilds = false }

        do {
            if let attached = try await service.fetchAttachedBuild(versionId: versionId) {
                attachedBuildByVersion[versionId] = attached
            } else {
                attachedBuildByVersion.removeValue(forKey: versionId)
            }
            if surfaceErrors {
                lastError = nil
            }
        } catch {
            if surfaceErrors {
                handleError(error)
            }
        }
    }

    func refreshApps() async {
        guard let service = appStoreService else {
            bootstrapWithMockData()
            return
        }

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let previouslySelected = selectedAppId
            apps = try await service.fetchApps()
            isUsingMockData = false
            connectionStatus = "Connected to App Store Connect"
            lastError = nil

            // Keep the user on whatever app they had selected if it still
            // exists after the refresh; only fall back to the first app (or
            // clear) when the selection is gone or nothing was selected.
            if let previouslySelected, apps.contains(where: { $0.id == previouslySelected }) {
                await refreshLiveVersionsForSelectedApp()
                return  // selection still valid — keep it, but refresh version/build state.
            }

            versionsByApp = [:]
            resetWorkspaceSelection()
            if let firstApp = apps.first {
                await selectLiveApp(firstApp.id)
            } else {
                selectedAppId = nil
                selectedVersionId = nil
            }
        } catch {
            handleError(error)
        }
    }

    internal func existingLocalizationId(for locale: String) -> String? {
        localeNotes.first(where: { $0.locale == locale })?.remoteLocalizationId
            ?? storeCopyLocales.first(where: { $0.locale == locale })?.remoteLocalizationId
            ?? remoteNotesByLocale[locale]?.localizationId
    }

    /// Resolve (or create) the localization for `locale` on `versionId`.
    ///
    /// Loaded localization IDs belong to the selected version only, so they are
    /// consulted — and newly learned IDs written back — only while `versionId`
    /// is still selected. Long operations that outlive a version switch pass the
    /// ID they captured up front via `knownLocalizationId`.
    internal func ensureLocalizationId(
        for locale: String,
        versionId: String,
        service: AppStoreConnectServicing,
        text: String = "",
        knownLocalizationId: String? = nil
    ) async throws -> String {
        if let knownLocalizationId {
            return knownLocalizationId
        }
        let isSelectedVersion = selectedVersionId == versionId
        if isSelectedVersion, let id = existingLocalizationId(for: locale) {
            return id
        }

        let noteText = text.isEmpty && isSelectedVersion
            ? (localeNotes.first { $0.locale == locale }?.localText ?? "")
            : text
        let created: RemoteLocaleNote
        do {
            created = try await service.createLocalization(
                versionId: versionId,
                locale: locale,
                text: transformedTextForSync(noteText)
            )
        } catch {
            guard isDuplicateLocalizationError(error),
                  let existing = try await refreshExistingLocalization(
                    locale: locale,
                    versionId: versionId,
                    service: service
                  ) else {
                throw error
            }
            return existing.localizationId
        }

        if selectedVersionId == versionId {
            applyRemoteLocalizationIdentity(created)
        }
        return created.localizationId
    }

    internal func isDuplicateLocalizationError(_ error: Error) -> Bool {
        guard case AppStoreConnectClientError.requestFailed(let statusCode, let message) = error,
              statusCode == 409 else {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("already exists")
            || normalized.contains("duplicate")
            || normalized.contains("attribute.invalid.duplicate")
    }

    internal func refreshExistingLocalization(
        locale: String,
        versionId: String,
        service: AppStoreConnectServicing
    ) async throws -> RemoteLocaleNote? {
        let remoteNotes = try await service.fetchLocalizations(versionId: versionId)
        if selectedVersionId == versionId {
            remoteNotes.forEach(applyRemoteLocalizationIdentity)
        }
        return remoteNotes.first { $0.locale.caseInsensitiveCompare(locale) == .orderedSame }
    }

    internal func applyRemoteLocalizationIdentity(_ remote: RemoteLocaleNote) {
        let locale = remote.locale
        var merged = remote
        if let existing = remoteNotesByLocale[locale] {
            merged.storeMetadata = remote.storeMetadata == .empty ? existing.storeMetadata : remote.storeMetadata
        }
        remoteNotesByLocale[locale] = merged

        applyRemoteIdentity(merged)
        if let copyIndex = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
            storeCopyLocales[copyIndex].remoteLocalizationId = merged.localizationId
        }
    }

    internal func configureLiveClient(_ credentials: AppStoreConnectCredentials) {
        let credentials = (try? credentials.validated()) ?? credentials.trimmed
        appStoreService = AppStoreConnectClient(credentials: credentials)
        credentialSummary = credentials.summary
        isUsingMockData = false
        accounts = [account(from: credentials)]
    }

    internal func account(from credentials: AppStoreConnectCredentials) -> Account {
        Account(
            id: "app-store-connect-\(credentials.keyId)",
            name: credentials.accountName,
            issuerId: credentials.issuerId,
            keyId: credentials.keyId,
            privateKeyReference: "keychain:org.shipnotes.app.appstoreconnect",
            createdAt: Date(),
            lastUsedAt: Date()
        )
    }

    internal func selectMockApp(_ id: String) {
        if selectedAppId != id {
            resetScreenshotWorkspace()
        }
        selectedAppId = id
        resetWorkspaceSelection()
        let versions = versionsByApp[id] ?? []
        if let editable = versions.first(where: { $0.canEditMetadata }) ?? versions.first {
            selectMockVersion(editable.id)
        } else {
            selectedVersionId = nil
        }
    }

    internal func selectMockVersion(_ id: String) {
        selectedVersionId = id
        pendingScreenshotReplacement = nil
        resetRemoteScreenshotCounts()
        sourceFolder = nil
        sourceDescription = "Mock sample data"
        watching = false
        loadMockNotesForCurrentVersion()
    }

    internal func selectLiveApp(_ id: String) async {
        guard let service = appStoreService else { return }
        let requestedAppId = id
        if selectedAppId != id {
            resetScreenshotWorkspace()
        }
        selectedAppId = id
        selectedVersionId = nil
        resetWorkspaceSelection()

        do {
            let versions = try await service.fetchVersions(appId: id)
            guard selectedAppId == requestedAppId else { return }
            versionsByApp[id] = versions
            if let editable = versions.first(where: { $0.canEditMetadata }) ?? versions.first {
                await selectLiveVersion(editable.id, resetSource: true)
            } else {
                lastError = nil
            }
        } catch {
            guard selectedAppId == requestedAppId else { return }
            handleError(error)
        }
    }

    internal func refreshLiveVersionsForSelectedApp() async {
        guard let service = appStoreService, let appId = selectedAppId else { return }
        let requestedAppId = appId
        let previousVersionId = selectedVersionId

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let versions = try await service.fetchVersions(appId: appId)
            guard selectedAppId == requestedAppId else { return }
            versionsByApp[appId] = versions
            let previous = versions.first { $0.id == previousVersionId }
            let preferred = previous?.canEditMetadata == true
                ? previous
                : (versions.first { $0.canEditMetadata } ?? previous ?? versions.first)

            lastError = nil
            if let preferred, preferred.id != previousVersionId {
                await selectLiveVersion(preferred.id, resetSource: true)
            } else {
                selectedVersionId = preferred?.id
                if let versionId = selectedVersionId {
                    await refreshAttachedBuild(versionId: versionId, surfaceErrors: true)
                }
            }
        } catch {
            guard selectedAppId == requestedAppId else { return }
            handleError(error)
        }
    }

    internal func selectLiveVersion(_ id: String, resetSource: Bool) async {
        guard let service = appStoreService else { return }
        let requestedAppId = selectedAppId
        let requestedVersionId = id
        // Switching versions invalidates any sync in flight: cancel it and bump
        // the generation so a late response can't write the old version's text
        // into the state we are about to load.
        cancelSync()
        selectedVersionId = id
        pendingScreenshotReplacement = nil
        resetRemoteScreenshotCounts()
        remoteNotesByLocale = [:]
        storeCopyLocales = []
        selectedStoreCopyLocale = nil
        if resetSource {
            sourceFolder = nil
            sourceDescription = nil
            watching = false
            retargetFileWatcher()
            localeNotes = []
            selectedLocale = nil
        }

        do {
            let remoteNotes = try await service.fetchLocalizations(versionId: id)
            guard selectedAppId == requestedAppId, selectedVersionId == requestedVersionId else { return }
            remoteNotesByLocale = Dictionary(uniqueKeysWithValues: remoteNotes.map { ($0.locale, $0) })
            applyLocalAndRemote(locales: [:], sourceFiles: [:], useRemoteAsLocalWhenMissing: true)
            refreshRemoteScreenshotCountsIfNeeded()
            lastError = nil
            await refreshAttachedBuild(versionId: id, surfaceErrors: true)
        } catch {
            guard selectedAppId == requestedAppId, selectedVersionId == requestedVersionId else { return }
            handleError(error)
        }
    }

    func bootstrapForLaunch() async {
        bootstrapWithMockData()
        Task {
            await reloadAIServiceFromKeychainInBackground(allowsAuthenticationUI: false)
        }
        Task {
            await reloadVisionAIServiceFromKeychainInBackground(allowsAuthenticationUI: false)
        }
        Task {
            await bootstrapLiveClientFromKeychainInBackground()
        }
        Task {
            await bootstrapAppleAdsFromKeychainInBackground()
        }
    }

    internal func bootstrapLiveClientFromKeychainInBackground() async {
        let store = credentialStore
        let loadResult = await Task.detached(priority: .userInitiated) { () -> CredentialLoadResult in
            do {
                return .success(try store.load())
            } catch let error as AppStoreConnectCredentialError {
                return .failure(error)
            } catch {
                return .failure(.invalidStoredData)
            }
        }.value

        do {
            guard case let .success(credentials) = loadResult else {
                if case let .failure(error) = loadResult {
                    handleError(error)
                }
                return
            }
            guard let credentials else { return }
            configureLiveClient(credentials)
            do {
                try await appStoreService?.validateCredentials()
            } catch {
                // Validation failed: rolling back to mock data keeps the app
                // from sitting in a mixed state (real client + mock app list)
                // that would send mock version IDs to Apple's API.
                bootstrapWithMockData()
                connectionStatus = "Stored credentials were rejected"
                handleError(error)
                return
            }
            await refreshApps()
            connectionStatus = "Connected to App Store Connect"
        }
    }

    func bootstrapWithMockData() {
        // Inject the in-memory service so sync/create/submit share the live
        // code path. `isUsingMockData` still gates UI that must not hit Apple.
        appStoreService = SampleAppStoreConnectService()
        isUsingMockData = true
        isLoadingRemote = false
        isSyncing = false
        syncActivityToken = nil
        connectionStatus = "Using mock sample data"
        credentialSummary = nil
        resetWorkspaceSelection()
        resetScreenshotWorkspace()
        accounts = [MockAppStoreConnect.sampleAccount()]
        apps = MockAppStoreConnect.sampleApps()
        versionsByApp = [:]
        for app in apps {
            versionsByApp[app.id] = MockAppStoreConnect.sampleVersions(for: app.id)
        }
        if let firstApp = apps.first {
            selectMockApp(firstApp.id)
        }
    }

    func saveCredentials(name: String, issuerId: String, keyId: String, privateKeyPEM: String) async {
        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let existingPrivateKey = try credentialStore.load()?.privateKeyPEM ?? ""
            let trimmedPrivateKey = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = try AppStoreConnectCredentials(
                name: name,
                issuerId: issuerId,
                keyId: keyId,
                privateKeyPEM: trimmedPrivateKey.isEmpty ? existingPrivateKey : privateKeyPEM
            )
            .validated()

            try credentialStore.save(credentials)
            configureLiveClient(credentials)
            try await appStoreService?.validateCredentials()
            await refreshApps()
            connectionStatus = "Connected to App Store Connect"
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func testConnection() async {
        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let credentials: AppStoreConnectCredentials
            if let stored = try credentialStore.load() {
                credentials = stored
            } else {
                throw AppStoreConnectCredentialError.missingPrivateKey
            }
            configureLiveClient(credentials)
            try await appStoreService?.validateCredentials()
            connectionStatus = "Connection test passed"
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func removeCredentials() {
        do {
            try credentialStore.delete()
            bootstrapWithMockData()
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func selectApp(_ id: String) {
        // Branch on `isUsingMockData`, not `appStoreService == nil`. Sample
        // mode now has a service, but selection must still load local drafts
        // that differ from remote so the first-run diff is visible.
        if isUsingMockData {
            selectMockApp(id)
        } else {
            Task { await selectLiveApp(id) }
        }
    }

    func selectVersion(_ id: String) {
        if isUsingMockData {
            selectMockVersion(id)
        } else {
            Task { await selectLiveVersion(id, resetSource: true) }
        }
    }

    func refreshSelectedAppVersions() {
        guard let appId = selectedAppId else { return }
        if isUsingMockData {
            Task {
                if let versions = try? await appStoreService?.fetchVersions(appId: appId) {
                    versionsByApp[appId] = versions
                }
            }
        } else {
            Task { await refreshLiveVersionsForSelectedApp() }
        }
    }

}
