import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    /// Shared by the toolbar and the workspace action so both reflect the
    /// same selected locale, validation state and version lock.
    var canSyncSelectedStoreCopy: Bool {
        guard !isSyncing, selectedVersion?.canEditMetadata == true,
            let selected = selectedStoreCopy
        else { return false }
        return selected.status == .ready || selected.status == .needsReview
    }

    /// Shared by the workspace's Sync All button and the ⌘S menu command.
    var canSyncAllStoreCopy: Bool {
        !isSyncing
            && selectedVersion?.canEditMetadata == true
            && storeCopyStats.pendingSyncCount > 0
    }

    func updateStoreCopyField(for locale: String, field: StoreCopyField, text: String) {
        guard let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { return }
        // URLs never legitimately carry surrounding whitespace, and raw
        // whitespace fails Apple's RFC 3986 check.
        let normalized =
            field.isURLField
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : text
        storeCopyLocales[index].localMetadata.setValue(normalized, for: field)
        recalculateStoreCopy(at: index)
    }

    func revertStoreCopyToRemote(_ locale: String) {
        guard let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { return }
        storeCopyLocales[index].localMetadata = storeCopyLocales[index].remoteMetadata ?? .empty
        recalculateStoreCopy(at: index)
    }

    func optimizeStoreCopyLocale(_ locale: String) {
        guard !isAIRunning else { return }
        guard let copy = storeCopyLocales.first(where: { $0.locale == locale }) else { return }
        guard aiService.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return
        }

        let appName = selectedApp?.name ?? "App"
        let versionString = selectedVersion?.versionString
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        isAIRunning = true
        aiActivity = AIActivity(startedAt: Date(), message: L("AI is optimizing %@ store copy…", locale))
        Task {
            defer {
                self.isAIRunning = false
                self.aiActivity = nil
            }
            do {
                let optimized = try await aiService.optimizeStoreMetadata(
                    metadata: copy.localMetadata,
                    locale: locale,
                    appName: appName,
                    versionString: versionString
                )
                guard self.selectedAppId == requestedAppId,
                    self.selectedVersionId == requestedVersionId
                else { return }
                guard let index = self.storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { return }
                self.bumpAICallCount()
                // Apply AI text only to fields still holding what was sent;
                // a field edited while the request ran keeps the user's text.
                // URLs are never rewritten by optimization.
                var merged = self.storeCopyLocales[index].localMetadata
                for field in StoreCopyField.allCases where !field.isURLField {
                    if merged.value(for: field) == copy.localMetadata.value(for: field) {
                        merged.setValue(optimized.value(for: field), for: field)
                    }
                }
                self.storeCopyLocales[index].localMetadata = merged
                self.recalculateStoreCopy(at: index)
                self.lastError = nil
            } catch {
                guard self.selectedAppId == requestedAppId,
                    self.selectedVersionId == requestedVersionId
                else { return }
                self.handleError(error)
            }
        }
    }

    func syncStoreCopyLocale(_ locale: String) {
        guard !isSyncing else { return }
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        syncTask = Task { await syncLiveStoreCopyLocales([locale], generation: generation) }
    }

    func syncStoreCopyField(locale: String, field: StoreCopyField) {
        guard !isSyncing else { return }
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        syncTask = Task { await syncLiveStoreCopyField(locale: locale, field: field, generation: generation) }
    }

    func syncAllStoreCopy() {
        guard !isSyncing else { return }
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        syncTask = Task { await syncLiveStoreCopyLocales(storeCopyLocales.map(\.locale), generation: generation) }
    }

    /// Reclassify rows left in `.syncing` / `.failed` by an earlier sync so a
    /// retried sync actually re-attempts them instead of hitting the `default`
    /// skip branch, and so a row can't be stuck showing "syncing" forever
    /// (see the matching release-notes recovery).
    func recoverStaleStoreCopyStates() {
        for index in storeCopyLocales.indices {
            switch storeCopyLocales[index].status {
            case .failed, .syncing:
                recalculateStoreCopy(at: index)
            default:
                break
            }
        }
    }

    private enum StoreCopyLoadOutcome: Sendable {
        case parsed(ParsedStoreCopy, source: URL)
        case fallbackToAI(nearbySource: URL?, originalMessage: String)
    }

    func loadStoreCopySource(_ url: URL) {
        storeCopySourceURL = url
        let parser = self.storeCopyParser
        let defaultLocale = selectedStoreCopyLocale ?? selectedLocale
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId

        Task {
            // Parsing + the nearby-source directory walk are file I/O; keep
            // them off the main actor (parser is a stateless struct).
            let outcome = await Task.detached(priority: .userInitiated) { () -> StoreCopyLoadOutcome in
                do {
                    let parsed = try parser.parse(url: url, defaultLocale: defaultLocale)
                    return .parsed(parsed, source: url)
                } catch {
                    let nearbySource = Self.nearbyStoreCopySource(for: url)
                    if let nearbySource, nearbySource.standardizedFileURL != url.standardizedFileURL {
                        if let parsed = try? parser.parse(
                            url: nearbySource,
                            defaultLocale: defaultLocale
                        ) {
                            return .parsed(parsed, source: nearbySource)
                        }
                        // Keep falling through to AI. The nearby source is still
                        // a better prompt root than a screenshot-only leaf folder.
                    }
                    return .fallbackToAI(
                        nearbySource: nearbySource,
                        originalMessage: error.localizedDescription
                    )
                }
            }.value

            guard selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }

            switch outcome {
            case .parsed(let parsed, let source):
                applyImportedStoreCopy(parsed)
                storeCopySourceURL = source
                storeCopySourceDescription = L("Imported from %@", parsed.sourceDescription)
                lastError = nil
            case .fallbackToAI(let nearbySource, let originalMessage):
                if aiService.isConfigured {
                    askAIToParseStoreCopy(url: nearbySource ?? url)
                } else {
                    setError(originalMessage)
                }
            }
        }
    }

    nonisolated internal static func nearbyStoreCopySource(for url: URL) -> URL? {
        let fm = FileManager.default
        let original = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: original.path, isDirectory: &isDir) else { return nil }

        var current = isDir.boolValue ? original : original.deletingLastPathComponent()
        var candidates: [URL] = []
        for _ in 0..<7 {
            candidates.append(contentsOf: FileScannerUtils.metadataFolderCandidates(under: current))
            candidates.append(contentsOf: [
                current.appending(path: "AppStore"),
                current,
            ])
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }

        var seen = Set<String>()
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard standardized != original else { continue }
            guard seen.insert(standardized.path).inserted else { continue }
            if storeCopySourceLooksReadable(standardized) {
                return standardized
            }
        }
        return nil
    }

    nonisolated private static func storeCopySourceLooksReadable(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        let supportedExts: Set<String> = ["md", "markdown", "txt", "yaml", "yml", "json"]
        if !isDir.boolValue {
            return supportedExts.contains(url.pathExtension.lowercased())
        }

        func walk(_ folder: URL, depth: Int) -> Bool {
            guard depth <= 3 else { return false }
            let entries =
                (try? fm.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    if walk(entry, depth: depth + 1) { return true }
                } else if supportedExts.contains(entry.pathExtension.lowercased()) {
                    return true
                }
            }
            return false
        }

        return walk(url, depth: 0)
    }

    var canReparseCurrentStoreCopyWithAI: Bool {
        storeCopySourceURL != nil && aiService.isConfigured && !isAIRunning
    }

    var storeCopyAIReparseHelp: String {
        guard storeCopySourceURL != nil else {
            return L("Import store copy before asking AI to re-parse.")
        }
        guard aiService.isConfigured else {
            return L("Configure AI in Settings first.")
        }
        if isAIRunning {
            return L("AI is already running.")
        }
        return L("Ask AI to re-extract store copy from the current source.")
    }

    func askAIToReparseCurrentStoreCopy() {
        guard let url = storeCopySourceURL else {
            setError(L("Import store copy before asking AI to re-parse."))
            return
        }
        askAIToParseStoreCopy(url: url)
    }

    func askAIToParseStoreCopy(url: URL) {
        let defaultLocale = selectedStoreCopyLocale ?? selectedLocale
        let known = Set(storeCopyLocales.map(\.locale))
            .union(remoteNotesByLocale.keys)
            .sorted()
        let appName = selectedApp?.name ?? "App"
        let versionString = selectedVersion?.versionString
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        Task {
            await runAIStoreCopyParse(
                url: url,
                defaultLocale: defaultLocale,
                knownRemoteLocales: known,
                appName: appName,
                versionString: versionString,
                requestedAppId: requestedAppId,
                requestedVersionId: requestedVersionId
            )
        }
    }

    func runAIStoreCopyParse(
        url: URL,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?,
        requestedAppId: String?,
        requestedVersionId: String?
    ) async {
        guard selectedAppId == requestedAppId,
            selectedVersionId == requestedVersionId
        else { return }
        guard !isAIRunning else { return }
        guard aiService.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return
        }
        isAIRunning = true
        aiActivity = AIActivity(startedAt: Date(), message: L("AI is reading %@…", url.lastPathComponent))
        defer {
            self.isAIRunning = false
            self.aiActivity = nil
        }

        do {
            let text = try await Self.readTextForAI(at: url)
            let metadata = try await aiService.parseStoreMetadata(
                text: text,
                defaultLocale: defaultLocale,
                knownRemoteLocales: knownRemoteLocales,
                appName: appName,
                versionString: versionString
            )
            // The parse landed after one or more suspensions - bail if the
            // user switched app/version in the meantime.
            guard !Task.isCancelled,
                selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }
            let partials = Dictionary(
                uniqueKeysWithValues: metadata.map { locale, fields in
                    (locale, Self.partialStoreMetadata(from: fields))
                })
            let sourceFiles = Dictionary(uniqueKeysWithValues: metadata.keys.map { ($0, url) })
            let parsed = ParsedStoreCopy(
                locales: partials,
                sourceFiles: sourceFiles,
                sourceDescription: "AI · \(url.lastPathComponent)"
            )
            self.bumpAICallCount()
            self.applyImportedStoreCopy(parsed)
            self.storeCopySourceURL = url
            self.storeCopySourceDescription = L("Imported from %@", parsed.sourceDescription)
            self.lastError = nil
        } catch {
            guard selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }
            if case AIServiceError.noContentExtracted = error {
                self.setError(L("AI could not extract any store copy from this file."))
            } else {
                self.handleError(error)
            }
        }
    }

    func presentStoreCopyImportPicker() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Import")
        panel.message = L("Select a store-copy file, metadata folder, or project folder.")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in self.loadStoreCopySource(url) }
        }
        #endif
    }

    func rebuildStoreCopyLocales() {
        let knownLocales = Set(localeNotes.map(\.locale))
            .union(remoteNotesByLocale.keys)
            .union(storeCopyLocales.map(\.locale))
        let existingByLocale = Dictionary(uniqueKeysWithValues: storeCopyLocales.map { ($0.locale, $0) })
        let rows = knownLocales.sorted().map { locale in
            let remote = remoteNotesByLocale[locale]
            let existing = existingByLocale[locale]
            let localMetadata = existing?.localMetadata ?? remote?.storeMetadata ?? .empty
            return makeStoreCopy(locale: locale, localMetadata: localMetadata, remoteNote: remote)
        }
        storeCopyLocales = rows
        if let selectedStoreCopyLocale, rows.contains(where: { $0.locale == selectedStoreCopyLocale }) {
            return
        }
        selectedStoreCopyLocale = rows.first?.locale
    }

    func applyImportedStoreCopy(_ parsed: ParsedStoreCopy) {
        var importedLocales: [String] = []
        for (locale, partial) in parsed.locales {
            guard !partial.isEmpty else { continue }
            importedLocales.append(locale)
            if let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
                storeCopyLocales[index].localMetadata = partial.applying(to: storeCopyLocales[index].localMetadata)
                recalculateStoreCopy(at: index)
            } else {
                let remote = remoteNotesByLocale[locale]
                let metadata = partial.applying(to: remote?.storeMetadata ?? .empty)
                storeCopyLocales.append(makeStoreCopy(locale: locale, localMetadata: metadata, remoteNote: remote))
            }
        }

        storeCopyLocales.sort { $0.locale.localizedStandardCompare($1.locale) == .orderedAscending }
        if let selected = importedLocales.sorted().first {
            selectedStoreCopyLocale = selected
        } else if selectedStoreCopyLocale == nil {
            selectedStoreCopyLocale = storeCopyLocales.first?.locale
        }
    }

    internal static func partialStoreMetadata(from fields: StoreMetadataFields) -> PartialStoreMetadataFields {
        var partial = PartialStoreMetadataFields()
        for field in StoreCopyField.allCases {
            partial.setValue(fields.value(for: field), for: field)
        }
        return partial
    }

    func makeStoreCopy(
        locale: String,
        localMetadata: StoreMetadataFields,
        remoteNote: RemoteLocaleNote?
    ) -> StoreCopyLocale {
        let remoteMetadata = remoteNote?.storeMetadata
        let issues = validateStoreMetadata(localMetadata)
        let changedCount = StoreCopyField.allCases.filter { field in
            field.isVersionLocalizationField
                && localMetadata.value(for: field) != (remoteMetadata?.value(for: field) ?? "")
        }.count
        let status = computeStoreCopyStatus(
            localMetadata: localMetadata,
            remoteMetadata: remoteMetadata,
            changedFieldCount: changedCount,
            issues: issues
        )
        return StoreCopyLocale(
            locale: locale,
            remoteLocalizationId: remoteNote?.localizationId,
            localMetadata: localMetadata,
            remoteMetadata: remoteMetadata,
            status: status,
            changedFieldCount: changedCount,
            validationIssues: issues
        )
    }

    func recalculateStoreCopy(at index: Int) {
        let row = storeCopyLocales[index]
        let issues = validateStoreMetadata(row.localMetadata)
        let changedCount = StoreCopyField.allCases.filter { field in
            field.isVersionLocalizationField
                && row.localMetadata.value(for: field) != (row.remoteMetadata?.value(for: field) ?? "")
        }.count
        storeCopyLocales[index].validationIssues = issues
        storeCopyLocales[index].changedFieldCount = changedCount
        storeCopyLocales[index].status = computeStoreCopyStatus(
            localMetadata: row.localMetadata,
            remoteMetadata: row.remoteMetadata,
            changedFieldCount: changedCount,
            issues: issues
        )
    }

    func validateStoreMetadata(_ metadata: StoreMetadataFields) -> [StoreCopyIssue] {
        var issues: [StoreCopyIssue] = []
        if metadata.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    field: .description,
                    severity: .error,
                    message: L("Description cannot be empty")
                ))
        }

        for field in StoreCopyField.allCases {
            let value = metadata.value(for: field)
            if let limit = field.limit, value.count > limit {
                issues.append(
                    .init(
                        field: field,
                        severity: .error,
                        message: L(
                            "%1$@ exceeds App Store limit of %2$d characters (currently %3$d)", field.title, limit,
                            value.count)
                    ))
            }
            if !field.isURLField, validator.containsMarkdown(value) {
                issues.append(
                    .init(
                        field: field,
                        severity: .warning,
                        message: L("%@ contains Markdown syntax. App Store shows plain text.", field.title)
                    ))
            }
        }

        for field in StoreCopyField.allCases where field.isURLField {
            let value = metadata.value(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard Self.isValidHTTPURL(value) else {
                issues.append(
                    .init(
                        field: field,
                        severity: .error,
                        message: L("%@ must be a valid http:// or https:// URL.", field.title)
                    ))
                continue
            }
            guard Self.isPercentEncodedURI(value) else {
                issues.append(
                    .init(
                        field: field,
                        severity: .error,
                        message: L(
                            "%@ contains spaces or unencoded non-ASCII characters. Percent-encode the URL before syncing.",
                            field.title)
                    ))
                continue
            }
        }
        return issues
    }

    internal static func isValidHTTPURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host?.isEmpty == false
        else {
            return false
        }
        return true
    }

    /// RFC 3986 allows only these characters (plus valid `%XX` escapes) in a
    /// URI. Foundation's `URLComponents` accepts raw spaces and non-ASCII,
    /// which Apple's server then rejects with a 409, so check explicitly.
    nonisolated internal static let uriAllowedCharacters: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%"
    )

    nonisolated internal static func isPercentEncodedURI(_ value: String) -> Bool {
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character.isASCII, uriAllowedCharacters.contains(character) else { return false }
            if character == "%" {
                guard characters.indices.contains(index + 2),
                    characters[index + 1].isASCII, characters[index + 1].hexDigitValue != nil,
                    characters[index + 2].isASCII, characters[index + 2].hexDigitValue != nil
                else {
                    return false
                }
                index += 3
                continue
            }
            index += 1
        }
        return true
    }

    /// Returns false when any locale failed, so submit-for-review can abort
    /// without relying on the global `lastError`.
    @discardableResult
    func syncLiveStoreCopyLocales(_ locales: [String], generation: UUID? = nil) async -> Bool {
        guard let service = appStoreService, let versionId = selectedVersionId else { return false }
        let requestedAppId = selectedAppId
        recoverStaleStoreCopyStates()
        let activity = beginSyncActivity()
        defer { endSyncActivity(activity) }

        var results: [String: LocaleSyncResult] = [:]
        for locale in locales {
            // Same staleness guard as release-notes sync: a response landing
            // after the user switched app/version must not be written into
            // the new selection.
            if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }

            guard let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { continue }
            let row = storeCopyLocales[index]
            switch row.status {
            case .ready, .needsReview:
                storeCopyLocales[index].status = .syncing
                do {
                    let localizationId: String
                    if let existingId = row.remoteLocalizationId {
                        localizationId = existingId
                    } else {
                        let whatsNew = localeNotes.first { $0.locale == locale }?.localText ?? ""
                        localizationId = try await ensureLocalizationId(
                            for: locale,
                            versionId: versionId,
                            service: service,
                            text: whatsNew
                        )
                    }

                    let remote = try await service.updateStoreMetadata(
                        localizationId: localizationId,
                        metadata: row.localMetadata
                    )
                    if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }
                    remoteNotesByLocale[locale] = remote
                    applyRemoteIdentity(remote)
                    if let updatedIndex = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
                        storeCopyLocales[updatedIndex].remoteLocalizationId = remote.localizationId
                        storeCopyLocales[updatedIndex].remoteMetadata = remote.storeMetadata
                        // A version-localization response does not contain app-info fields.
                        // Preserve those drafts, and any edits made during the request.
                        for field in StoreCopyField.allCases where field.isVersionLocalizationField {
                            if storeCopyLocales[updatedIndex].localMetadata.value(for: field)
                                == row.localMetadata.value(for: field)
                            {
                                storeCopyLocales[updatedIndex].localMetadata.setValue(
                                    remote.storeMetadata.value(for: field), for: field)
                            }
                        }
                        recalculateStoreCopy(at: updatedIndex)
                        if storeCopyLocales[updatedIndex].changedFieldCount == 0,
                            storeCopyLocales[updatedIndex].validationIssues.allSatisfy({ $0.severity != .error })
                        {
                            storeCopyLocales[updatedIndex].status = .synced
                        }
                    }
                    results[locale] = .succeeded
                } catch {
                    if Self.isCancellation(error) { return false }
                    if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }
                    if let updatedIndex = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
                        storeCopyLocales[updatedIndex].status = .failed(error.localizedDescription)
                    }
                    results[locale] = .failed(error.localizedDescription)
                    handleError(error)
                }
            case .overLimit:
                setError(L("Store copy has fields over the App Store limit."))
                results[locale] = .failed(L("Store copy has fields over the App Store limit."))
            case .invalid:
                // Name the offending field instead of only the generic banner.
                let detail =
                    storeCopyLocales[index].validationIssues
                    .first { $0.severity == .error }?.message
                    ?? L("Store copy has invalid fields. Fix them before syncing.")
                setError(detail)
                results[locale] = .failed(detail)
            case .missing:
                setError(L("Store description cannot be empty."))
                results[locale] = .failed(L("Store description cannot be empty."))
            default:
                continue
            }
        }

        if !results.isEmpty {
            recordSyncRun(
                localeResults: results,
                dryRun: false,
                kind: .storeCopy,
                appId: requestedAppId,
                versionId: versionId
            )
        }
        // Clear the banner only when the whole batch succeeded — clearing
        // per-locale would wipe an error raised by an earlier row in the
        // same run.
        if !results.values.contains(where: {
            if case .failed = $0 { return true }; return false
        }) {
            lastError = nil
        }
        return !results.values.contains { if case .failed = $0 { true } else { false } }
    }

    func syncLiveStoreCopyField(locale: String, field: StoreCopyField, generation: UUID? = nil) async {
        guard let service = appStoreService, let versionId = selectedVersionId else { return }
        guard let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { return }
        guard storeCopyFieldCanSync(storeCopyLocales[index], field: field) else { return }
        let requestedAppId = selectedAppId

        // Don't let a field sync interleave with a locale-wide sync — both
        // PATCH the same localization.
        guard !isSyncing else { return }
        recoverStaleStoreCopyStates()
        let activity = beginSyncActivity()
        defer { endSyncActivity(activity) }

        let row = storeCopyLocales[index]
        storeCopyLocales[index].status = .syncing

        do {
            let localizationId: String
            if let existingId = row.remoteLocalizationId {
                localizationId = existingId
            } else {
                let whatsNew = localeNotes.first { $0.locale == locale }?.localText ?? ""
                localizationId = try await ensureLocalizationId(
                    for: locale,
                    versionId: versionId,
                    service: service,
                    text: whatsNew
                )
            }

            let value = row.localMetadata.value(for: field)
            let remote = try await service.updateStoreMetadataField(
                localizationId: localizationId,
                field: field,
                value: value
            )
            // Same staleness guard as the other live syncs: never write a
            // response into a selection the user has already moved away from.
            if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return }

            var remoteMetadata = row.remoteMetadata ?? remote.storeMetadata
            remoteMetadata.setValue(value, for: field)
            remoteNotesByLocale[locale] = RemoteLocaleNote(
                localizationId: remote.localizationId,
                locale: remote.locale,
                text: remote.text,
                storeMetadata: remoteMetadata
            )
            applyRemoteIdentity(remote)
            if let updatedIndex = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
                storeCopyLocales[updatedIndex].remoteLocalizationId = remote.localizationId
                storeCopyLocales[updatedIndex].remoteMetadata = remoteMetadata
                recalculateStoreCopy(at: updatedIndex)
                if storeCopyLocales[updatedIndex].changedFieldCount == 0 {
                    storeCopyLocales[updatedIndex].status = .synced
                }
            }
            lastError = nil
        } catch {
            if Self.isCancellation(error) { return }
            if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return }
            if let updatedIndex = storeCopyLocales.firstIndex(where: { $0.locale == locale }) {
                storeCopyLocales[updatedIndex].status = .failed(error.localizedDescription)
            }
            handleError(error)
        }
    }

    func storeCopyFieldCanSync(_ row: StoreCopyLocale, field: StoreCopyField) -> Bool {
        guard field.isVersionLocalizationField else { return false }
        let localValue = row.localMetadata.value(for: field)
        let remoteValue = row.remoteMetadata?.value(for: field) ?? ""
        guard localValue != remoteValue else { return false }
        // The PATCH omits empty URL attributes (Apple rejects ""), so it can't
        // clear a URL that exists remotely — say so instead of silently no-op'ing.
        if field.isURLField,
            localValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !remoteValue.isEmpty
        {
            setError(L("%@ cannot be cleared on App Store Connect. Replace it with a different URL.", field.title))
            return false
        }
        if let error = row.validationIssues.first(where: { $0.field == field && $0.severity == .error }) {
            setError(error.message)
            return false
        }
        return true
    }

    func computeStoreCopyStatus(
        localMetadata: StoreMetadataFields,
        remoteMetadata: StoreMetadataFields?,
        changedFieldCount: Int,
        issues: [StoreCopyIssue]
    ) -> LocaleStatus {
        if localMetadata.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missing
        }
        if issues.contains(where: { $0.severity == .error }) {
            // Reserve "Over Limit" for genuine character-count overflows; other
            // blocking errors (e.g. a malformed URL) get the generic "Invalid"
            // status instead of being mislabeled as over the limit.
            let hasOverLimit = issues.contains { issue in
                guard issue.severity == .error, let limit = issue.field.limit else { return false }
                return localMetadata.value(for: issue.field).count > limit
            }
            return hasOverLimit ? .overLimit : .invalid
        }
        if remoteMetadata != nil && changedFieldCount == 0 {
            return .noChange
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .needsReview
        }
        return .ready
    }

    func selectStoreCopyLocale(_ code: String) {
        selectedStoreCopyLocale = code
    }

}
