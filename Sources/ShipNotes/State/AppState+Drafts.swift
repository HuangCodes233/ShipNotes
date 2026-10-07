import CryptoKit
import Foundation

@MainActor
extension AppState {
    var workspaceDraftAccountID: String? {
        if isUsingMockData { return "sample" }
        guard let summary = credentialSummary else { return nil }
        let identity = summary.issuerId + "\u{0}" + summary.keyId
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var currentWorkspaceDraftKey: WorkspaceDraftKey? {
        guard let accountID = workspaceDraftAccountID,
            let appID = selectedAppId, let versionID = selectedVersionId
        else { return nil }
        return WorkspaceDraftKey(accountID: accountID, appID: appID, versionID: versionID)
    }

    var preferredWorkspaceDraftAppID: String? {
        guard let accountID = workspaceDraftAccountID else { return nil }
        return workspaceDrafts.values.filter { $0.key.accountID == accountID }
            .max { $0.savedAt < $1.savedAt }?.key.appID
    }

    func preferredWorkspaceDraftVersionID(for appID: String) -> String? {
        guard let accountID = workspaceDraftAccountID else { return nil }
        return workspaceDrafts.values.filter { $0.key.accountID == accountID && $0.key.appID == appID }
            .max { $0.savedAt < $1.savedAt }?.key.versionID
    }

    func loadWorkspaceDrafts() {
        do {
            workspaceDrafts = Dictionary(
                try workspaceDraftStore.load().map { ($0.key, $0) },
                uniquingKeysWith: { first, second in
                    first.savedAt > second.savedAt ? first : second
                })
        } catch {
            // Never replace unreadable drafts with an empty file on the next
            // keystroke. Edits remain available in memory for this session.
            workspaceDraftPersistenceBlocked = true
            reportWorkspaceDraftError(error, loading: true)
        }
    }

    /// Snapshot before selection changes. Capturing now (rather than after the
    /// debounce) makes switching apps safe while an autosave is waiting.
    func saveCurrentWorkspaceDraft() {
        guard !isRestoringWorkspaceDraft else { return }
        captureCurrentWorkspaceDraft()
        queueWorkspaceDraftWrite()
    }

    func scheduleWorkspaceDraftSave() {
        saveCurrentWorkspaceDraft()
    }

    /// Synchronous and idempotent so termination can flush without depending on
    /// a task getting another opportunity to run.
    func persistWorkspaceDraftsNow() {
        workspaceDraftSaveTask?.cancel()
        workspaceDraftSaveTask = nil
        if !isRestoringWorkspaceDraft { captureCurrentWorkspaceDraft() }
        writeWorkspaceDrafts()
    }

    private func queueWorkspaceDraftWrite() {
        workspaceDraftSaveTask?.cancel()
        workspaceDraftSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }
            self.workspaceDraftSaveTask = nil
            self.writeWorkspaceDrafts()
        }
    }

    private func writeWorkspaceDrafts() {
        guard !workspaceDraftPersistenceBlocked else { return }
        do {
            try workspaceDraftStore.save(workspaceDrafts.values.sorted { $0.savedAt > $1.savedAt })
            if let previousError = workspaceDraftSaveError, lastError?.message == previousError {
                lastError = nil
            }
            workspaceDraftSaveError = nil
        } catch {
            reportWorkspaceDraftError(error, loading: false)
        }
    }

    private func reportWorkspaceDraftError(_ error: Error, loading: Bool) {
        let message =
            loading
            ? L(
                "Workspace drafts could not be opened. The existing draft file has been preserved. %@",
                error.localizedDescription)
            : L(
                "Workspace drafts could not be saved. Your edits are still available in this session. %@",
                error.localizedDescription)
        workspaceDraftSaveError = message
        setError(message, category: .fileIO, isRetryable: !loading)
    }

    private func captureCurrentWorkspaceDraft() {
        guard let key = currentWorkspaceDraftKey else { return }
        // Selection changes precede the asynchronous localization fetch. Until
        // restore establishes the new baseline, any remaining screenshot state
        // still belongs to the previous workspace and must not replace this
        // version's saved text with an empty loading snapshot.
        if let loadedKey = workspaceDraftBaselineKey, loadedKey != key { return }
        // An empty workspace while a new version is loading is not a deletion
        // of that version's saved edits.
        guard !localeNotes.isEmpty || !storeCopyLocales.isEmpty || screenshotFolder != nil else { return }
        var snapshot = WorkspaceDraft(key: key, savedAt: Date(), workspaceMode: workspaceMode.rawValue)
        let existing = workspaceDrafts[key]
        for note in localeNotes where note.localText != (note.remoteText ?? "") {
            let baseline =
                workspaceDraftBaselineKey == key
                ? workspaceDraftReleaseBaselines[note.locale] ?? existing?.releaseNotes[note.locale]?.sourceBaseline
                : nil
            let sourceBaseline = baseline ?? note.remoteText ?? note.localText
            snapshot.releaseNotes[note.locale] = WorkspaceDraftText(
                text: note.localText, remoteBaseline: note.remoteText, sourceBaseline: sourceBaseline,
                wasEdited: note.localText != sourceBaseline)
        }
        for row in storeCopyLocales {
            var fields: [String: WorkspaceDraftText] = [:]
            for field in StoreCopyField.allCases {
                let local = row.localMetadata.value(for: field)
                let remote = row.remoteMetadata?.value(for: field)
                guard local != (remote ?? "") else { continue }
                let baseline =
                    workspaceDraftBaselineKey == key
                    ? workspaceDraftStoreCopyBaselines[row.locale]?[field.rawValue]
                        ?? existing?.storeCopy[row.locale]?[field.rawValue]?.sourceBaseline
                    : nil
                let sourceBaseline = baseline ?? remote ?? local
                fields[field.rawValue] = WorkspaceDraftText(
                    text: local, remoteBaseline: remote, sourceBaseline: sourceBaseline,
                    wasEdited: local != sourceBaseline)
            }
            if !fields.isEmpty { snapshot.storeCopy[row.locale] = fields }
        }
        snapshot.releaseSourceURL = sourceFolder
        snapshot.storeCopySourceURL = storeCopySourceURL
        snapshot.selectedLocale = selectedLocale
        snapshot.selectedStoreCopyLocale = selectedStoreCopyLocale
        snapshot.selectedScreenshotLocale = selectedScreenshotLocale
        if workspaceDraftScreenshotRestoreKey == key && isScanningScreenshots && screenshotFolder == nil,
            let existing
        {
            snapshot.screenshotFolder = existing.screenshotFolder
            snapshot.screenshotAssetHashes = existing.screenshotAssetHashes
            snapshot.screenshotLocaleOverrides = existing.screenshotLocaleOverrides
            snapshot.screenshotSharedAssetIDs = existing.screenshotSharedAssetIDs
            snapshot.screenshotOrderByGroup = existing.screenshotOrderByGroup
        } else {
            snapshot.screenshotFolder = screenshotFolder
            snapshot.screenshotAssetHashes = Dictionary(
                (screenshotScan?.assets ?? []).compactMap { asset in
                    asset.contentHash.map { (asset.id, $0) }
                }, uniquingKeysWith: { _, second in second })
            snapshot.screenshotLocaleOverrides = screenshotAILocaleOverrides
            snapshot.screenshotSharedAssetIDs = screenshotAISharedAssetIDs
            snapshot.screenshotOrderByGroup = screenshotOrderByGroup
        }
        workspaceDrafts[key] = snapshot
    }

    /// Restores only local values. Fresh remote text, localization IDs and
    /// validation remain authoritative. Source reloads replace untouched fields
    /// but preserve manual edits, reporting conflicting incoming changes.
    func restoreCurrentWorkspaceDraft(afterSourceReload: Bool = false) {
        guard let key = currentWorkspaceDraftKey else { return }
        let snapshot = workspaceDrafts[key]
        let isNewWorkspace = workspaceDraftBaselineKey != key
        // Recompute conflicts from the incoming content. A warning from a
        // different workspace or an already-published draft must not linger.
        if lastError?.message == workspaceDraftConflictError { lastError = nil }
        workspaceDraftConflictError = nil
        isRestoringWorkspaceDraft = true
        defer { isRestoringWorkspaceDraft = false }
        workspaceDraftBaselineKey = key
        workspaceDraftReleaseBaselines = Dictionary(
            localeNotes.map { ($0.locale, $0.localText) }, uniquingKeysWith: { _, second in second })
        workspaceDraftStoreCopyBaselines = Dictionary(
            storeCopyLocales.map { row in
                (
                    row.locale,
                    Dictionary(
                        uniqueKeysWithValues: StoreCopyField.allCases.map {
                            ($0.rawValue, row.localMetadata.value(for: $0))
                        })
                )
            }, uniquingKeysWith: { _, second in second })
        var conflicts = false
        if let snapshot {
            for (locale, draft) in snapshot.releaseNotes {
                guard !afterSourceReload || draft.wasEdited else { continue }
                if let index = localeNotes.firstIndex(where: { $0.locale == locale }) {
                    let incoming = localeNotes[index]
                    guard draft.text != (incoming.remoteText ?? "") else { continue }
                    conflicts =
                        conflicts
                        || (afterSourceReload
                            ? incoming.localText != draft.sourceBaseline && incoming.localText != draft.text
                            : incoming.remoteText != draft.remoteBaseline && incoming.remoteText != draft.text)
                    localeNotes[index].localText = draft.text
                    recalculate(at: index)
                } else {
                    localeNotes.append(
                        makeNote(
                            locale: locale, localText: draft.text, remoteNote: remoteNotesByLocale[locale], path: nil))
                }
                workspaceDraftReleaseBaselines[locale] = draft.sourceBaseline
            }
            for (locale, fields) in snapshot.storeCopy {
                if !storeCopyLocales.contains(where: { $0.locale == locale }) {
                    guard !afterSourceReload || fields.values.contains(where: \.wasEdited) else { continue }
                    let remote = remoteNotesByLocale[locale]
                    storeCopyLocales.append(
                        makeStoreCopy(
                            locale: locale, localMetadata: remote?.storeMetadata ?? .empty, remoteNote: remote))
                }
                guard let index = storeCopyLocales.firstIndex(where: { $0.locale == locale }) else { continue }
                for (fieldName, draft) in fields {
                    guard let field = StoreCopyField(rawValue: fieldName),
                        !afterSourceReload || draft.wasEdited
                    else { continue }
                    let incoming = storeCopyLocales[index]
                    let remote = incoming.remoteMetadata?.value(for: field)
                    guard draft.text != (remote ?? "") else { continue }
                    conflicts =
                        conflicts
                        || (afterSourceReload
                            ? incoming.localMetadata.value(for: field) != draft.sourceBaseline
                                && incoming.localMetadata.value(for: field) != draft.text
                            : remote != draft.remoteBaseline && remote != draft.text)
                    storeCopyLocales[index].localMetadata.setValue(draft.text, for: field)
                    workspaceDraftStoreCopyBaselines[locale, default: [:]][fieldName] = draft.sourceBaseline
                }
                recalculateStoreCopy(at: index)
            }
            localeNotes.sort { $0.locale.localizedStandardCompare($1.locale) == .orderedAscending }
            storeCopyLocales.sort { $0.locale.localizedStandardCompare($1.locale) == .orderedAscending }
            if !afterSourceReload {
                sourceFolder = existingDraftSource(snapshot.releaseSourceURL)
                sourceDescription = sourceFolder.map { L("Restored from %@", $0.lastPathComponent) }
                storeCopySourceURL = existingDraftSource(snapshot.storeCopySourceURL)
                storeCopySourceDescription = storeCopySourceURL.map { L("Restored from %@", $0.lastPathComponent) }
                // Restoring a source never re-parses it or sends it to AI.
                watching = false
                retargetFileWatcher()
                if let mode = WorkspaceMode(rawValue: snapshot.workspaceMode) { workspaceMode = mode }
                if localeNotes.contains(where: { $0.locale == snapshot.selectedLocale }) {
                    selectedLocale = snapshot.selectedLocale
                }
                if storeCopyLocales.contains(where: { $0.locale == snapshot.selectedStoreCopyLocale }) {
                    selectedStoreCopyLocale = snapshot.selectedStoreCopyLocale
                }
            }
        }
        if !afterSourceReload && isNewWorkspace {
            resetScreenshotWorkspace()
            if let folder = existingDraftSource(snapshot?.screenshotFolder) {
                workspaceDraftScreenshotRestoreKey = key
                loadScreenshotsFolder(folder)
            }
        }
        if conflicts {
            let message = L(
                "The source or remote content changed. Your edited draft was kept; review the differences before syncing."
            )
            workspaceDraftConflictError = message
            setError(message)
        }
    }

    /// Called after a saved folder has been scanned again. Classifications are
    /// restored only for identical file contents, never for replaced images.
    func restoreScreenshotWorkspaceDraft() {
        guard let key = currentWorkspaceDraftKey else { return }
        workspaceDraftScreenshotRestoreKey = nil
        guard let snapshot = workspaceDrafts[key], snapshot.screenshotFolder == screenshotFolder,
            let scan = screenshotScan
        else { return }
        let unchangedIDs = Set(
            scan.assets.compactMap { asset -> String? in
                guard let hash = asset.contentHash, snapshot.screenshotAssetHashes[asset.id] == hash else { return nil }
                return asset.id
            })
        screenshotAILocaleOverrides = snapshot.screenshotLocaleOverrides.filter { unchangedIDs.contains($0.key) }
        screenshotAISharedAssetIDs = snapshot.screenshotSharedAssetIDs.intersection(unchangedIDs)
        screenshotOrderByGroup = snapshot.screenshotOrderByGroup.mapValues { $0.filter { unchangedIDs.contains($0) } }
        screenshotCoverageGroupsCache = nil
        screenshotIssuesCache = nil
        if screenshotCoverageGroups.contains(where: { $0.locale == snapshot.selectedScreenshotLocale }) {
            selectedScreenshotLocale = snapshot.selectedScreenshotLocale
        }
    }

    private func existingDraftSource(_ url: URL?) -> URL? {
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
