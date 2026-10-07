import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    func askAIToParse(url: URL) {
        let version = selectedVersion?.versionString
        let known = remoteNotesByLocale.keys.sorted()
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        Task {
            await runAIParse(
                url: url,
                currentVersion: version,
                knownRemoteLocales: known,
                requestedAppId: requestedAppId,
                requestedVersionId: requestedVersionId
            )
        }
    }

    var canReparseCurrentReleaseNotesWithAI: Bool {
        sourceFolder != nil && aiService.isConfigured && !isAIRunning
    }

    var releaseNotesAIReparseHelp: String {
        guard sourceFolder != nil else {
            return L("Import a release-notes source before asking AI to re-parse.")
        }
        guard aiService.isConfigured else {
            return L("Configure AI in Settings first.")
        }
        if isAIRunning {
            return L("AI is already running.")
        }
        return L("Ask AI to re-extract release notes from the current source.")
    }

    func askAIToReparseCurrentReleaseNotes() {
        guard let url = sourceFolder else {
            setError(L("Import a release-notes source before asking AI to re-parse."))
            return
        }
        askAIToParse(url: url)
    }

    func translateAllEmptyLocales(from sourceLocale: String) {
        guard !isAIRunning else { return }
        guard let sourceText = localeNotes.first(where: { $0.locale == sourceLocale })?.localText,
            !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            setError(L("Source locale has no text to translate."))
            return
        }
        guard aiService.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return
        }

        let targets =
            localeNotes
            .filter { note in
                note.locale != sourceLocale
                    && note.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map(\.locale)

        guard !targets.isEmpty else { return }

        let captured = aiService
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        isAIRunning = true
        let totalCount = targets.count
        aiActivity = AIActivity(
            startedAt: Date(),
            message: L("AI is translating %d locale(s)…", totalCount)
        )
        Task {
            defer {
                self.isAIRunning = false
                self.aiActivity = nil
            }
            var lastFailure: String?
            for (index, target) in targets.enumerated() {
                guard self.selectedAppId == requestedAppId,
                    self.selectedVersionId == requestedVersionId
                else { return }
                let currentStart = Date()
                let progressIndex = index + 1
                self.aiActivity = AIActivity(
                    startedAt: currentStart,
                    message: L("AI is translating %1$@ (%2$d / %3$d)…", target, progressIndex, totalCount)
                )
                do {
                    let translated = try await captured.translate(
                        text: sourceText,
                        fromLocale: sourceLocale,
                        toLocale: target,
                        glossary: [:]
                    )
                    // Bail (silently) if the user switched selection mid-run -
                    // the translations belong to the version they started from.
                    guard self.selectedAppId == requestedAppId,
                        self.selectedVersionId == requestedVersionId
                    else { return }
                    self.bumpAICallCount()
                    // Targets were chosen because they were empty. A long run
                    // can take minutes; never replace text typed meanwhile.
                    let stillEmpty =
                        self.localeNotes.first { $0.locale == target }?
                        .localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false
                    if stillEmpty {
                        self.updateLocalText(for: target, text: translated)
                    }
                } catch {
                    guard self.selectedAppId == requestedAppId,
                        self.selectedVersionId == requestedVersionId
                    else { return }
                    lastFailure = error.localizedDescription
                    // Continue translating other locales rather than abort.
                }
            }
            self.lastError = lastFailure.map {
                AppError($0, category: .ai, isRetryable: false)
            }
        }
    }

    func translateLocale(_ targetLocale: String, fromLocale sourceLocale: String) {
        guard !isAIRunning else { return }
        guard sourceLocale != targetLocale else { return }
        guard let sourceText = localeNotes.first(where: { $0.locale == sourceLocale })?.localText,
            !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            setError(L("Source locale has no text to translate."))
            return
        }
        guard aiService.isConfigured else {
            handleError(AIServiceError.notConfigured)
            return
        }
        isAIRunning = true
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        let originalTargetText = localeNotes.first { $0.locale == targetLocale }?.localText
        aiActivity = AIActivity(startedAt: Date(), message: L("AI is translating to %@…", targetLocale))
        Task {
            defer {
                self.isAIRunning = false
                self.aiActivity = nil
            }
            do {
                let translated = try await aiService.translate(
                    text: sourceText,
                    fromLocale: sourceLocale,
                    toLocale: targetLocale,
                    glossary: [:]
                )
                guard self.selectedAppId == requestedAppId,
                    self.selectedVersionId == requestedVersionId
                else { return }
                self.bumpAICallCount()
                guard self.localeNotes.first(where: { $0.locale == targetLocale })?.localText == originalTargetText
                else {
                    self.setError(
                        L("%@ was edited while AI was translating, so the translation was not applied.", targetLocale),
                        category: .ai
                    )
                    return
                }
                self.updateLocalText(for: targetLocale, text: translated)
                self.clearLastErrorPreservingWorkspaceDraftError()
            } catch {
                guard self.selectedAppId == requestedAppId,
                    self.selectedVersionId == requestedVersionId
                else { return }
                self.handleError(error)
            }
        }
    }

    func runAIParse(
        url: URL,
        currentVersion: String?,
        knownRemoteLocales: [String],
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
            let locales = try await aiService.parseReleaseNotes(
                text: text,
                currentVersion: currentVersion,
                knownRemoteLocales: knownRemoteLocales
            )
            // The parse landed after one or more suspensions - bail if the
            // user switched app/version in the meantime.
            guard !Task.isCancelled,
                selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }
            let sourceFiles = Dictionary(uniqueKeysWithValues: locales.keys.map { ($0, url) })
            let parsed = ParsedReleaseNotes(
                version: currentVersion,
                locales: locales,
                sourceFiles: sourceFiles,
                sourceDescription: "AI · \(url.lastPathComponent)",
                candidatesByLocale: [:]
            )
            self.bumpAICallCount()
            self.clearPendingImport()
            self.clearLastErrorPreservingWorkspaceDraftError()
            self.applyImportedReleaseNotes(parsed, sourceURL: url)
        } catch {
            guard selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }
            self.handleError(error)
        }
    }

    private enum FolderLoadOutcome: Sendable {
        case parsed(ParsedReleaseNotes)
        case versionNotFound
        case suppressedScreenshotFolder
        case unparseable(String)
    }

    func loadFolder(_ url: URL) {
        let parser = self.parser
        // Capture the selection the import was started from so a slow parse
        // can't land its result into a different app/version.
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        let currentVersion = selectedVersion?.versionString
        // With Watch Folder on, saves arrive in quick succession; a slower,
        // older parse must not land after (and overwrite) a newer one.
        let requestID = UUID()
        folderLoadRequestID = requestID

        Task {
            // Directory walking + file reads run off the main actor; the
            // parser is a stateless struct, safe to use from a detached task.
            let outcome = await Task.detached(priority: .userInitiated) { () -> FolderLoadOutcome in
                do {
                    let parsed = try parser.parse(url: url, currentVersion: currentVersion)
                    return .parsed(parsed)
                } catch {
                    // Only a version mismatch is a definitive answer; every
                    // other parse failure falls through to the AI fallback.
                    if case ReleaseNotesParserError.versionNotFound = error {
                        return .versionNotFound
                    }
                    if Self.shouldSuppressAIReleaseNotesFallback(for: url) {
                        return .suppressedScreenshotFolder
                    }
                    return .unparseable(error.localizedDescription)
                }
            }.value

            guard folderLoadRequestID == requestID,
                selectedAppId == requestedAppId,
                selectedVersionId == requestedVersionId
            else { return }

            switch outcome {
            case .parsed(let parsed):
                clearLastErrorPreservingWorkspaceDraftError()
                if parsed.requiresReview {
                    pendingImport = parsed
                    pendingImportURL = url
                    pendingImportSelections = parsed.defaultCandidateSelections
                    pendingImportSelectedLocale = parsed.candidatesByLocale.keys.sorted().first
                } else {
                    applyImportedReleaseNotes(parsed, sourceURL: url)
                }
            case .versionNotFound:
                handleError(ReleaseNotesParserError.versionNotFound(currentVersion ?? ""))
            case .suppressedScreenshotFolder:
                setError(
                    L(
                        "This looks like screenshot documentation, not release notes. Import screenshot folders from the Screenshots tab, or choose a release-notes file."
                    ))
            case .unparseable(let message):
                // Deterministic parser couldn't make sense of this folder/file.
                // If the user has connected an AI provider, automatically fall
                // back to LLM extraction (saves them from "drop → error → click
                // button → wait" friction every time a new folder layout shows up).
                if aiService.isConfigured {
                    askAIToParse(url: url)
                } else {
                    setError(message)
                }
            }
        }
    }

    nonisolated internal static func shouldSuppressAIReleaseNotesFallback(for url: URL) -> Bool {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        let pathLooksScreenshotRelated =
            path.contains("/screenshots/")
            || path.contains("/screenshot/")
            || path.contains("/appstore/screenshots/")
            || name.contains("screenshot")
            || name.contains("capture")

        guard pathLooksScreenshotRelated else { return false }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return true
        }

        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let normalized = text.lowercased()
        let screenshotSignals = [
            "screenshot",
            "screenshots",
            "screenshot checklist",
            "app store connect",
            "iphone 6.5",
            "iphone 6.9",
            "ipad 13",
            "capture",
            "device size",
        ]
        let signalCount = screenshotSignals.filter { normalized.contains($0) }.count
        return name == "readme.md" || signalCount >= 2
    }

    func confirmPendingImport() {
        guard var parsed = pendingImport else { return }
        parsed.locales = parsed.resolvedLocales(using: pendingImportSelections)
        applyImportedReleaseNotes(parsed, sourceURL: pendingImportURL)
        clearPendingImport()
    }

    func cancelPendingImport() {
        clearPendingImport()
    }

    func toggleWatching() {
        watching.toggle()
        retargetFileWatcher()
    }

    /// Point the folder watcher at the current `sourceFolder`, or tear it down
    /// when watching is off / there is nothing to watch.
    func retargetFileWatcher() {
        guard watching else {
            fileWatcher.stop()
            return
        }
        guard let folder = sourceFolder else {
            fileWatcher.stop()
            watching = false
            return
        }
        fileWatcher.start(url: folder) { [weak self] in
            self?.reloadFromSource()
        }
    }

    func reloadFromSource() {
        guard let folder = sourceFolder else { return }
        loadFolder(folder)
    }

    func presentImportPicker() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Import")
        panel.message = L("Select a release-notes folder, YAML, JSON, or CHANGELOG.md.")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in self.loadFolder(url) }
        }
        #endif
    }

    func importURL(_ url: URL, for mode: WorkspaceMode? = nil) {
        switch mode ?? workspaceMode {
        case .releaseNotes:
            loadFolder(url)
        case .storeCopy:
            loadStoreCopySource(url)
        case .screenshots:
            loadScreenshotsFolder(url)
        case .ads:
            break
        }
    }

    func presentImportPickerForCurrentWorkspace() {
        switch workspaceMode {
        case .releaseNotes:
            presentImportPicker()
        case .storeCopy:
            presentStoreCopyImportPicker()
        case .screenshots:
            presentScreenshotPicker()
        case .ads:
            break
        }
    }

    /// ⌘R entry point shared by the toolbar help text and the menu command.
    func askAIToReparseCurrentWorkspace() {
        switch workspaceMode {
        case .releaseNotes:
            askAIToReparseCurrentReleaseNotes()
        case .storeCopy:
            askAIToReparseCurrentStoreCopy()
        case .screenshots, .ads:
            break
        }
    }

    func revertToRemote(_ locale: String) {
        guard let index = localeNotes.firstIndex(where: { $0.locale == locale }) else { return }
        localeNotes[index].localText = localeNotes[index].remoteText ?? ""
        recalculate(at: index)
        scheduleWorkspaceDraftSave()
    }

    func copyLocalText(_ locale: String) {
        guard let note = localeNotes.first(where: { $0.locale == locale }) else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.localText, forType: .string)
        #endif
    }

    func syncLocale(_ locale: String) {
        guard !isSyncing else { return }
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        syncTask = Task { await syncLiveLocales([locale], generation: generation) }
    }

    func updateLocalText(for locale: String, text: String) {
        guard let index = localeNotes.firstIndex(where: { $0.locale == locale }) else { return }
        localeNotes[index].localText = text
        recalculate(at: index)
        scheduleWorkspaceDraftSave()
    }

    /// Shared by the bottom bar and the ⌘D menu command.
    var canDryRunReleaseNotes: Bool {
        !localeNotes.isEmpty
            && !isLoadingRemote
            && !isSyncing
            && selectedVersion?.canEditMetadata == true
    }

    /// Shared by the bottom bar's Sync All button and the ⌘S menu command, so
    /// a keyboard shortcut can't push to App Store Connect when the button
    /// would be disabled (locked version, nothing ready, sync in flight).
    var canSyncAllReleaseNotes: Bool {
        let stats = localeNotesStats
        return stats.readyCount + stats.needsReviewCount > 0
            && !isLoadingRemote
            && !isSyncing
            && selectedVersion?.canEditMetadata == true
    }

    /// Whether ⌘S does anything in the active workspace.
    var canPerformSyncCommand: Bool {
        switch workspaceMode {
        case .releaseNotes: canSyncAllReleaseNotes
        case .storeCopy: canSyncAllStoreCopy
        case .screenshots, .ads: false
        }
    }

    /// Whether ⌘D does anything in the active workspace.
    var canPerformDryRunCommand: Bool {
        workspaceMode == .releaseNotes && canDryRunReleaseNotes
    }

    /// Route the global ⌘S / ⌘D commands at the active workspace so the
    /// shortcuts do something sensible (and non-destructive) everywhere.
    func performDryRun() {
        guard canPerformDryRunCommand else { return }
        let run = SyncRun(
            id: UUID(),
            appId: selectedAppId ?? "",
            versionId: selectedVersionId ?? "",
            startedAt: Date(),
            completedAt: Date(),
            dryRun: true,
            localeResults: Dictionary(uniqueKeysWithValues: localeNotes.map { ($0.locale, projectedResult(for: $0)) })
        )
        appendSyncRun(run)
        dryRunCompletionTick &+= 1
    }

    func performSync() {
        // Never restart a running sync: cancelling mid-flight and starting
        // over is what a repeated ⌘S used to do.
        guard canPerformSyncCommand else { return }
        switch workspaceMode {
        case .releaseNotes:
            break
        case .storeCopy:
            syncAllStoreCopy()
            return
        case .screenshots, .ads:
            return
        }
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        syncTask = Task { await syncLiveLocales(localeNotes.map(\.locale), generation: generation) }
    }

    /// Async version of performSync for tests — awaits completion.
    func performSyncAsync() async {
        cancelSync()
        syncGeneration = UUID()
        let generation = syncGeneration
        await syncLiveLocales(localeNotes.map(\.locale), generation: generation)
    }

    /// Cancel any in-flight sync task and recover `.syncing` states.
    ///
    /// Bumping the generation is what makes cancellation work for syncs we hold
    /// no task handle for (`performSyncAsync`, and any sync already suspended
    /// inside a network call): they check the generation after every `await` and
    /// drop their results instead of writing them into current state.
    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        syncGeneration = UUID()
        recoverSyncingStates()
        recoverStaleStoreCopyStates()
    }

    /// True when the sync that carries `generation` no longer owns the state it
    /// is about to write — either it was superseded/cancelled, or the user moved
    /// to a different app/version while it was suspended.
    func isStaleSync(generation: UUID?, appId: String?, versionId: String) -> Bool {
        if Task.isCancelled { return true }
        if let generation, generation != syncGeneration { return true }
        return selectedAppId != appId || selectedVersionId != versionId
    }

    /// URLSession surfaces task cancellation as `URLError.cancelled` rather than
    /// `CancellationError`, so both spellings have to count as "user cancelled".
    internal static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    /// Reset any locales stuck in `.syncing` back to a ready state.
    func recoverSyncingStates() {
        for index in localeNotes.indices where localeNotes[index].status == .syncing {
            recalculate(at: index)
        }
        // `.failed` carries a stale error message but says nothing about the
        // current text — after an edit the row may be ready, or still over
        // the limit. Without this, a retried sync would hit the `default`
        // branch below and silently skip the locale forever.
        for index in localeNotes.indices {
            if case .failed = localeNotes[index].status {
                recalculate(at: index)
            }
        }
    }

    func applyImportedReleaseNotes(_ parsed: ParsedReleaseNotes, sourceURL: URL?) {
        saveCurrentWorkspaceDraft()
        let sourceChanged = sourceFolder != sourceURL
        sourceFolder = sourceURL
        sourceDescription = parsed.sourceDescription
        applyParsedLocales(parsed)
        restoreCurrentWorkspaceDraft(afterSourceReload: true)
        scheduleWorkspaceDraftSave()
        // Importing a *different* source moves an active watcher onto it. Never
        // touch the watcher when reloading the same folder: the watcher's own
        // callback arrives through this path (reloadFromSource → loadFolder),
        // so stopping here would make "Watch Folder" fire exactly once.
        if sourceChanged { retargetFileWatcher() }
    }

    func clearPendingImport() {
        pendingImport = nil
        pendingImportURL = nil
        pendingImportSelections = [:]
        pendingImportSelectedLocale = nil
    }

    func loadMockNotesForCurrentVersion() {
        guard let versionId = selectedVersionId else { return }
        let remote = MockAppStoreConnect.sampleRemoteNotes(versionId: versionId)
        let local = MockAppStoreConnect.sampleLocalNotes(versionId: versionId)
        let metadata = MockAppStoreConnect.sampleStoreMetadata(versionId: versionId)
        // IDs must match `SampleAppStoreConnectService.seededLocalizations`
        // so mock sync can PATCH the in-memory localization the UI is showing.
        remoteNotesByLocale = Dictionary(
            uniqueKeysWithValues: remote.map { locale, text in
                (
                    locale,
                    RemoteLocaleNote(
                        localizationId: "mock-\(versionId)-\(locale)",
                        locale: locale,
                        text: text,
                        storeMetadata: metadata[locale] ?? .empty
                    )
                )
            })
        applyLocalAndRemote(locales: local, sourceFiles: [:], useRemoteAsLocalWhenMissing: false)
    }

    func applyParsedLocales(_ parsed: ParsedReleaseNotes) {
        applyLocalAndRemote(
            locales: parsed.locales, sourceFiles: parsed.sourceFiles, useRemoteAsLocalWhenMissing: false)
    }

    func applyLocalAndRemote(locales: [String: String], sourceFiles: [String: URL], useRemoteAsLocalWhenMissing: Bool) {
        let allLocales = Set(locales.keys).union(remoteNotesByLocale.keys)
        let notes = allLocales.sorted().map { locale in
            let remote = remoteNotesByLocale[locale]
            let localText = locales[locale] ?? (useRemoteAsLocalWhenMissing ? remote?.text ?? "" : "")
            return makeNote(locale: locale, localText: localText, remoteNote: remote, path: sourceFiles[locale])
        }
        localeNotes = notes
        // Keep the locale being edited across reloads (every watched-folder
        // save lands here); fall back to the first one when it's gone.
        if !notes.contains(where: { $0.locale == selectedLocale }) {
            selectedLocale = notes.first?.locale
        }
        rebuildStoreCopyLocales()
    }

    func makeNote(locale: String, localText: String, remoteNote: RemoteLocaleNote?, path: URL?) -> LocaleNote {
        let issues = validator.validate(text: localText)
        let summary: DiffSummary? = remoteNote.map { diff.summary(old: $0.text, new: localText) }
        let status = computeStatus(localText: localText, remoteText: remoteNote?.text, summary: summary, issues: issues)
        return LocaleNote(
            locale: locale,
            localPath: path,
            remoteLocalizationId: remoteNote?.localizationId,
            localText: localText,
            remoteText: remoteNote?.text,
            status: status,
            diffSummary: summary,
            validationIssues: issues
        )
    }

    func recalculate(at index: Int) {
        let note = localeNotes[index]
        let issues = validator.validate(text: note.localText)
        let summary: DiffSummary? = note.remoteText.map { diff.summary(old: $0, new: note.localText) }
        let status = computeStatus(
            localText: note.localText, remoteText: note.remoteText, summary: summary, issues: issues)
        localeNotes[index].validationIssues = issues
        localeNotes[index].diffSummary = summary
        localeNotes[index].status = status
    }

    /// Merge a fetched remote localization's identity/text back into the
    /// matching `localeNotes` row (no-op when the locale isn't loaded). Used
    /// by the release-notes, store-copy, and ensure-localization sync paths.
    func applyRemoteIdentity(_ remote: RemoteLocaleNote) {
        guard let index = localeNotes.firstIndex(where: { $0.locale == remote.locale }) else { return }
        localeNotes[index].remoteLocalizationId = remote.localizationId
        localeNotes[index].remoteText = remote.text
        recalculate(at: index)
    }

    /// Returns false when any locale failed (or the sync was cancelled), so
    /// callers like submit-for-review can abort without relying on the
    /// global `lastError` (which may hold an unrelated, stale message).
    @discardableResult
    func syncLiveLocales(_ locales: [String], generation: UUID? = nil) async -> Bool {
        guard let service = appStoreService, let versionId = selectedVersionId else { return false }
        let requestedAppId = selectedAppId
        recoverSyncingStates()
        let activity = beginSyncActivity()
        defer { endSyncActivity(activity) }

        var results: [String: LocaleSyncResult] = [:]
        var cancelled = false
        localeLoop: for locale in locales {
            // Check cancellation and generation staleness at each iteration.
            if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }

            guard let index = localeNotes.firstIndex(where: { $0.locale == locale }) else { continue }
            let note = localeNotes[index]

            switch note.status {
            case .ready, .needsReview:
                let outgoing = transformedTextForSync(note.localText)
                localeNotes[index].status = .syncing
                do {
                    let remote: RemoteLocaleNote
                    if let localizationId = note.remoteLocalizationId {
                        remote = try await service.updateWhatsNew(localizationId: localizationId, text: outgoing)
                    } else {
                        let localizationId = try await ensureLocalizationId(
                            for: locale,
                            versionId: versionId,
                            service: service,
                            text: outgoing
                        )
                        remote = try await service.updateWhatsNew(localizationId: localizationId, text: outgoing)
                    }
                    // The response landed after one or more suspensions — the
                    // selection may have moved on. Writing now would put this
                    // version's text into whatever version is selected instead.
                    if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }
                    remoteNotesByLocale[locale] = remote
                    if let updatedIndex = localeNotes.firstIndex(where: { $0.locale == locale }) {
                        localeNotes[updatedIndex].remoteLocalizationId = remote.localizationId
                        // Only normalize the text we sent if it is still the
                        // current draft. A user can keep editing while PATCH
                        // is in flight; its response must not undo those edits.
                        if localeNotes[updatedIndex].localText == note.localText {
                            localeNotes[updatedIndex].localText = outgoing
                        }
                        localeNotes[updatedIndex].remoteText = remote.text
                        recalculate(at: updatedIndex)
                        if localeNotes[updatedIndex].localText == remote.text {
                            localeNotes[updatedIndex].status = .synced
                        }
                    }
                    scheduleWorkspaceDraftSave()
                    results[locale] = .succeeded
                } catch {
                    // A cancelled request is not a failure: don't paint the row
                    // red and don't log it to sync history.
                    if Self.isCancellation(error) {
                        cancelled = true
                        break localeLoop
                    }
                    if isStaleSync(generation: generation, appId: requestedAppId, versionId: versionId) { return false }
                    if let updatedIndex = localeNotes.firstIndex(where: { $0.locale == locale }) {
                        localeNotes[updatedIndex].status = .failed(error.localizedDescription)
                    }
                    results[locale] = .failed(error.localizedDescription)
                }
            case .overLimit:
                results[locale] = .failed(L("Over character limit"))
            case .invalid:
                results[locale] = .failed(
                    note.validationIssues.first { $0.severity == .error }?.message
                        ?? L(
                            "Some release notes could not be synced to App Store Connect. Fix the failed locales, then submit again."
                        ))
            case .missing:
                results[locale] = .skipped
            default:
                results[locale] = .skipped
            }
        }
        // A superseded sync must not touch rows: the newer sync may already
        // have marked them `.syncing`. `cancelSync()` recovered them for us.
        let isSuperseded = generation.map { $0 != syncGeneration } ?? false
        if cancelled && !isSuperseded { recoverSyncingStates() }
        if !results.isEmpty {
            recordSyncRun(
                localeResults: results,
                dryRun: false,
                appId: requestedAppId,
                versionId: versionId
            )
        }
        if cancelled { return false }
        let succeeded = !results.values.contains { if case .failed = $0 { true } else { false } }
        if succeeded { clearLastErrorPreservingWorkspaceDraftError() }
        return succeeded
    }

    /// Marks a sync as running. Only the most recently started sync may clear
    /// `isSyncing`: a cancelled sync that winds down late must not re-enable
    /// the sync buttons while its replacement is still writing.
    func beginSyncActivity() -> UUID {
        let token = UUID()
        syncActivityToken = token
        isSyncing = true
        return token
    }

    func endSyncActivity(_ token: UUID) {
        guard syncActivityToken == token else { return }
        syncActivityToken = nil
        isSyncing = false
    }

    func projectedResult(for note: LocaleNote) -> LocaleSyncResult {
        switch note.status {
        case .ready, .needsReview: .succeeded
        case .overLimit: .failed(L("Over character limit"))
        case .missing: .skipped
        default: .skipped
        }
    }

    func transformedTextForSync(_ text: String) -> String {
        guard defaults.bool(forKey: SettingsKey.stripMarkdownOnSync) else { return text }
        return validator.stripMarkdownToPlainText(text)
    }

    func computeStatus(
        localText: String, remoteText: String?, summary: DiffSummary?, issues: [ValidationIssue]
    ) -> LocaleStatus {
        if localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missing
        }
        // Check length directly — validation message text is localized so substring matching is unreliable.
        if localText.count > ValidationEngine.whatsNewCharacterLimit {
            return .overLimit
        }
        if let summary, !summary.hasChanges {
            return .noChange
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .needsReview
        }
        return .ready
    }

    func selectLocale(_ code: String) {
        selectedLocale = code
    }

}
