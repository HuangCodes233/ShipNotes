import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    func uploadSelectedScreenshotLocale() {
        guard let locale = selectedScreenshotGroup?.locale else { return }
        Task { await prepareScreenshotReplacementPreview(locales: [locale]) }
    }

    func uploadAllScreenshots() {
        Task { await prepareScreenshotReplacementPreview(locales: screenshotPreviewableLocales()) }
    }

    func dismissScreenshotReplacementPreview() {
        pendingScreenshotReplacement = nil
    }

    func confirmScreenshotReplacementPreview() {
        guard let plan = pendingScreenshotReplacement else { return }
        pendingScreenshotReplacement = nil
        Task { await uploadScreenshotReplacementPlan(plan) }
    }

    func selectScreenshotIssue(_ issue: ScreenshotIssue) {
        if let assetID = issue.assetIDs.first,
           let asset = screenshotScan?.assets.first(where: { $0.id == assetID }) {
            // Coverage groups use the canonical (version) locale, not the raw
            // scanner guess, so select the group the asset is shown in.
            let locale = canonicalScreenshotLocale(for: asset) ?? ScreenshotScan.unassignedLocaleDisplayName
            selectedScreenshotLocale = locale
            selectedScreenshotAssetId = assetID
            screenshotFocusTargetID = screenshotAssetFocusID(assetID)
            return
        }

        if let locale = issue.locale {
            selectedScreenshotLocale = locale
            selectedScreenshotAssetId = nil
            if let slot = issue.slot {
                screenshotFocusTargetID = screenshotSlotFocusID(locale: locale, slot: slot)
            } else {
                screenshotFocusTargetID = screenshotLocaleFocusID(locale)
            }
        }
    }

    func screenshotLocaleFocusID(_ locale: String) -> String {
        "screenshot-locale-\(locale)"
    }

    func screenshotSlotFocusID(locale: String, slot: ScreenshotDeviceSlot?) -> String {
        "screenshot-slot-\(locale)-\(slot?.rawValue ?? "unsupported")"
    }

    func screenshotAssetFocusID(_ assetID: String) -> String {
        "screenshot-asset-\(assetID)"
    }

    func refreshRemoteScreenshotCounts() {
        remoteScreenshotCountsTask?.cancel()
        let requestID = UUID()
        remoteScreenshotCountsRequestID = requestID
        remoteScreenshotCountsTask = Task { await loadRemoteScreenshotCounts(force: true, requestID: requestID) }
    }

    internal func refreshRemoteScreenshotCountsIfNeeded() {
        guard screenshotScan != nil, appStoreService != nil else { return }
        if remoteScreenshotCountsVersionId != selectedVersionId {
            remoteScreenshotCountsByLocale = [:]
        }
        let missingAnyLocale = screenshotCoverageLocales.contains {
            remoteScreenshotCountsByLocale[$0] == nil
        }
        guard missingAnyLocale, remoteScreenshotCountsTask == nil else { return }
        let requestID = UUID()
        remoteScreenshotCountsRequestID = requestID
        remoteScreenshotCountsTask = Task { await loadRemoteScreenshotCounts(force: false, requestID: requestID) }
    }

    internal func resetRemoteScreenshotCounts() {
        remoteScreenshotCountsTask?.cancel()
        remoteScreenshotCountsTask = nil
        remoteScreenshotCountsRequestID = nil
        remoteScreenshotCountsVersionId = selectedVersionId
        remoteScreenshotCountsByLocale = [:]
        isLoadingRemoteScreenshotCounts = false
    }

    internal func loadRemoteScreenshotCounts(force: Bool, requestID suppliedRequestID: UUID? = nil) async {
        let requestID = suppliedRequestID ?? UUID()
        if suppliedRequestID == nil {
            remoteScreenshotCountsTask?.cancel()
            remoteScreenshotCountsRequestID = requestID
        }
        guard let service = appStoreService else {
            resetRemoteScreenshotCounts()
            return
        }
        let versionId = selectedVersionId
        let locales = screenshotCoverageLocales
        guard screenshotScan != nil, !locales.isEmpty else {
            resetRemoteScreenshotCounts()
            return
        }
        if !force,
           remoteScreenshotCountsVersionId == versionId,
           locales.allSatisfy({ remoteScreenshotCountsByLocale[$0] != nil }) {
            if remoteScreenshotCountsRequestID == requestID {
                remoteScreenshotCountsTask = nil
                remoteScreenshotCountsRequestID = nil
            }
            return
        }

        let localizationIDs = Dictionary(
            uniqueKeysWithValues: locales.map { locale in
                (locale, existingLocalizationId(for: locale))
            }
        )

        isLoadingRemoteScreenshotCounts = true
        remoteScreenshotCountsVersionId = versionId
        defer {
            if remoteScreenshotCountsRequestID == requestID {
                isLoadingRemoteScreenshotCounts = false
                remoteScreenshotCountsTask = nil
                remoteScreenshotCountsRequestID = nil
            }
        }

        let fetched = await Self.fetchScreenshotSets(
            localizationIDs: localizationIDs.values.compactMap { $0 },
            service: service
        )
        var counts: [String: Int] = [:]
        for locale in locales {
            guard let localizationId = localizationIDs[locale] ?? nil else {
                counts[locale] = 0
                continue
            }
            // Count refresh is informational. Leave a failed locale unknown
            // instead of surfacing a blocking error banner.
            if case .success(let sets)? = fetched[localizationId] {
                counts[locale] = sets.reduce(0) { $0 + $1.screenshots.count }
            }
        }

        guard !Task.isCancelled,
              remoteScreenshotCountsRequestID == requestID,
              selectedVersionId == versionId else { return }
        remoteScreenshotCountsByLocale = counts
    }

    /// Fetches the screenshot sets of several localizations a few at a time.
    /// Serial per-locale fetches made large apps wait tens of seconds for
    /// counts and previews; four in flight mirrors the upload's concurrency.
    nonisolated internal static func fetchScreenshotSets(
        localizationIDs: [String],
        service: any AppStoreConnectServicing,
        maxConcurrent: Int = 4
    ) async -> [String: Result<[RemoteScreenshotSet], any Error>] {
        var seen = Set<String>()
        let ids = localizationIDs.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return [:] }

        // Two release-only (-O) codegen hazards shape this function on the
        // macOS 27.2 beta toolchain, both reproduced on the import path:
        // 1. TaskGroup teardown crashed in TaskGroup::offer — hence
        //    mapConcurrently's unstructured tasks (see ParallelMap.swift).
        // 2. Round-tripping the dictionary KEY string through a task return
        //    corrupted it (SIGSEGV hashing a zeroed String). Workers now
        //    return only the Result; keys come from `ids` by position, so a
        //    key never crosses an await boundary.
        let fetched = await mapConcurrently(
            ids,
            maxConcurrent: maxConcurrent
        ) { id -> Result<[RemoteScreenshotSet], any Error> in
            do {
                return .success(try await service.fetchScreenshotSets(localizationId: id))
            } catch {
                return .failure(error)
            }
        }
        var results = [String: Result<[RemoteScreenshotSet], any Error>]()
        results.reserveCapacity(ids.count)
        for index in ids.indices {
            results[ids[index]] = fetched[index]
        }
        return results
    }

    internal func screenshotPreviewableLocales() -> [String] {
        let issues = screenshotIssues
        let slots = Set(uploadableScreenshotSlots)
        return screenshotCoverageGroups
            .filter {
                !$0.isUnassigned
                    && !hasBlockingScreenshotIssue(locale: $0.locale, issues: issues)
                    && hasUploadableScreenshots($0.assets, slots: slots)
            }
            .map(\.locale)
    }

    internal func hasUploadableScreenshots(locale: String) -> Bool {
        hasUploadableScreenshots(effectiveScreenshotAssets(locale: locale), slots: Set(uploadableScreenshotSlots))
    }

    /// Ready screenshots in a slot that will actually be uploaded (an ignored
    /// iPad slot doesn't count), matching what the preview plan includes.
    internal func hasUploadableScreenshots(_ assets: [ScreenshotAsset], slots: Set<ScreenshotDeviceSlot>) -> Bool {
        assets.contains { asset in
            guard asset.status == .ready, let slot = asset.deviceSlot else { return false }
            return slots.contains(slot)
        }
    }

    internal func screenshotHasBlockingIssues(locale: String) -> Bool {
        screenshotIssues.contains { issue in
            issue.severity == .error && issue.locale == locale
        }
    }

    internal func prepareScreenshotReplacementPreview(locales: [String]) async {
        guard let service = appStoreService else {
            setError(L("Connect App Store Connect before uploading screenshots."), category: .auth)
            return
        }
        guard !locales.isEmpty else {
            setError(L("No uploadable screenshots found."))
            return
        }

        let requestID = UUID()
        screenshotPreviewRequestID = requestID
        let requestedAppId = selectedAppId
        let requestedVersionId = selectedVersionId
        isPreparingScreenshotReplacement = true
        screenshotUploadSummary = nil
        pendingScreenshotReplacement = nil
        defer {
            if screenshotPreviewRequestID == requestID {
                screenshotPreviewRequestID = nil
                isPreparingScreenshotReplacement = false
            }
        }

        var failures: [String] = []
        var candidates: [(locale: String, localizationId: String?)] = []
        for locale in locales {
            guard !screenshotHasBlockingIssues(locale: locale) else {
                failures.append(L("%@ has blocking screenshot issues.", locale))
                continue
            }
            candidates.append((locale, existingLocalizationId(for: locale)))
        }

        let remoteSetsByLocalization = await Self.fetchScreenshotSets(
            localizationIDs: candidates.compactMap(\.localizationId),
            service: service
        )
        // The remote screenshots and localization IDs belong to the version
        // that was selected when the preview started. Showing (and later
        // confirming) them after a switch would replace another version's set.
        guard screenshotPreviewRequestID == requestID,
              selectedAppId == requestedAppId,
              selectedVersionId == requestedVersionId else { return }

        var localePlans: [ScreenshotReplacementLocalePlan] = []
        for candidate in candidates {
            let locale = candidate.locale
            var remoteSets: [RemoteScreenshotSet] = []
            if let localizationId = candidate.localizationId {
                switch remoteSetsByLocalization[localizationId] {
                case .success(let sets)?:
                    remoteSets = sets
                case .failure(let error)?:
                    failures.append("\(locale): \(error.localizedDescription)")
                    continue
                case nil:
                    failures.append("\(locale): \(L("Remote screenshots could not be loaded."))")
                    continue
                }
            }

            var remoteBySlot: [ScreenshotDeviceSlot: [RemoteScreenshot]] = [:]
            for set in remoteSets {
                guard let slot = set.slot else { continue }
                remoteBySlot[slot, default: []].append(contentsOf: set.screenshots)
            }

            let slots = uploadableScreenshotSlots.compactMap { slot -> ScreenshotReplacementSlotPlan? in
                let localAssets = screenshotAssets(locale: locale, slot: slot)
                    .filter { $0.status == .ready }
                let remoteScreenshots = remoteBySlot[slot] ?? []
                guard !localAssets.isEmpty || !remoteScreenshots.isEmpty else { return nil }
                return ScreenshotReplacementSlotPlan(
                    slot: slot,
                    remoteScreenshots: remoteScreenshots,
                    localAssets: localAssets
                )
            }

            if slots.contains(where: \.replacesRemote) {
                localePlans.append(
                    ScreenshotReplacementLocalePlan(
                        locale: locale,
                        localizationId: candidate.localizationId,
                        slots: slots
                    )
                )
            }
        }

        if !failures.isEmpty {
            setError(failures.joined(separator: "\n"), category: .appStoreConnect, isRetryable: true)
        }
        guard !localePlans.isEmpty else {
            if failures.isEmpty {
                setError(L("No uploadable screenshots found."))
            }
            return
        }
        pendingScreenshotReplacement = ScreenshotReplacementPlan(
            locales: localePlans,
            appId: requestedAppId,
            versionId: requestedVersionId
        )
        if failures.isEmpty {
            lastError = nil
        }
    }

    internal func uploadScreenshotReplacementPlan(_ plan: ScreenshotReplacementPlan) async {
        guard let service = appStoreService, let versionId = plan.versionId ?? selectedVersionId else {
            setError(L("Connect App Store Connect before uploading screenshots."), category: .auth)
            return
        }
        let appId = plan.appId ?? selectedAppId
        guard !plan.locales.isEmpty else {
            setError(L("No uploadable screenshots found."))
            return
        }
        // Switching app or version dismisses the preview; a plan that no longer
        // matches the selection must not upload into a version the user has
        // navigated away from.
        guard versionId == selectedVersionId, appId == selectedAppId else {
            setError(L("The selected version changed. Preview the screenshot upload again."))
            return
        }
        // Evaluate blocking issues once, for the scan the user confirmed. The
        // locale tasks below may finish after the user has moved on.
        let blockedLocales = Set(plan.locales.map(\.locale).filter { screenshotHasBlockingIssues(locale: $0) })

        isUploadingScreenshots = true
        screenshotUploadSummary = nil
        let startedAt = Date()
        let uploadID = UUID()
        screenshotUploadRequestID = uploadID
        screenshotUploadActivity = AIActivity(startedAt: startedAt, message: L("Uploading screenshots…"))
        defer {
            isUploadingScreenshots = false
            screenshotUploadActivity = nil
            if screenshotUploadRequestID == uploadID {
                screenshotUploadRequestID = nil
            }
        }

        var uploadedCount = 0
        var uploadedLocales = 0
        var failures: [String] = []
        var results: [String: LocaleSyncResult] = [:]

        // Unstructured tasks, not a TaskGroup (see mapConcurrently): the
        // macOS 27.2 beta runtime crashed in TaskGroup::offer whenever a
        // group's teardown raced a completing child. Per-locale results stay
        // consistent because each task records into the run through uploadID
        // guards; results return in locale order instead of completion order.
        let indexedPlans = Array(plan.locales.enumerated())
        let uploadResults = await mapConcurrently(
            indexedPlans,
            maxConcurrent: 4
        ) { localeIndex, localePlan in
            await self.uploadSingleLocaleScreenshots(
                localePlan: localePlan,
                isBlocked: blockedLocales.contains(localePlan.locale),
                versionId: versionId,
                service: service,
                startedAt: startedAt,
                uploadID: uploadID,
                localeIndex: localeIndex,
                localeCount: plan.locales.count
            )
        }

        for res in uploadResults {
            switch res {
            case .success(let locale, let count):
                uploadedLocales += 1
                uploadedCount += count
                results[locale] = .succeeded
            case .skipped(let locale):
                results[locale] = .skipped
            case .failure(let locale, let error, let hadRemoteContent):
                // Replacement deletes old screenshots first. A failed run can
                // leave this locale empty or only partly uploaded.
                let message = hadRemoteContent
                    ? L("%1$@: %2$@ (replacement interrupted — old screenshots may have been deleted and new screenshots may be incomplete; refresh and retry this locale)", locale, error)
                    : "\(locale): \(error)"
                failures.append(message)
                results[locale] = .failed(error)
            case .blockingIssue(let locale):
                failures.append(L("%@ has blocking screenshot issues.", locale))
                results[locale] = .failed(L("Blocking screenshot issues"))
            }
        }

        if !results.isEmpty {
            recordSyncRun(
                localeResults: results,
                dryRun: false,
                kind: .screenshots,
                appId: appId,
                versionId: versionId
            )
        }
        if uploadedCount > 0 {
            screenshotUploadSummary = L("Uploaded %1$d screenshot(s) for %2$d locale(s).", uploadedCount, uploadedLocales)
        }
        if failures.isEmpty {
            lastError = nil
        } else {
            setError(failures.joined(separator: "\n"), category: .appStoreConnect, isRetryable: true)
        }
        if selectedAppId == appId, selectedVersionId == versionId {
            refreshRemoteScreenshotCounts()
        }
    }

    internal enum LocaleUploadResult: Sendable {
        case success(locale: String, count: Int)
        case skipped(locale: String)
        case failure(locale: String, error: String, hadRemoteContent: Bool)
        case blockingIssue(locale: String)
    }

    private func uploadSingleLocaleScreenshots(
        localePlan: ScreenshotReplacementLocalePlan,
        isBlocked: Bool,
        versionId: String,
        service: AppStoreConnectServicing,
        startedAt: Date,
        uploadID: UUID,
        localeIndex: Int,
        localeCount: Int
    ) async -> LocaleUploadResult {
        let locale = localePlan.locale
        guard !isBlocked else {
            return .blockingIssue(locale: locale)
        }

        var replacedSlotWithRemoteContent = false
        do {
            let localizationId = try await ensureLocalizationId(
                for: locale,
                versionId: versionId,
                service: service,
                knownLocalizationId: localePlan.localizationId
            )
            var localeUploadCount = 0

            for slotPlan in localePlan.replacingSlots {
                let assets = slotPlan.localAssets.filter { $0.status == .ready }
                guard !assets.isEmpty else { continue }
                if !slotPlan.remoteScreenshots.isEmpty {
                    replacedSlotWithRemoteContent = true
                }
                guard assets.count <= 10 else {
                    throw AppStoreConnectClientError.requestFailed(
                        statusCode: 400,
                        message: L("%1$@ has more than 10 screenshots for %2$@.", locale, slotPlan.slot.displayName)
                    )
                }

                self.screenshotUploadActivity = AIActivity(
                    startedAt: startedAt,
                    message: L(
                        "Uploading %1$@ · %2$@ · %3$d screenshot(s) · locale %4$d/%5$d…",
                        locale,
                        slotPlan.slot.displayName,
                        assets.count,
                        localeIndex + 1,
                        localeCount
                    )
                )

                localeUploadCount += try await service.replaceScreenshots(
                    localizationId: localizationId,
                    displayType: slotPlan.slot.appStoreConnectDisplayType,
                    files: assets.map(\.url),
                    onProgress: { [weak self] index, total, _ in
                        Task { @MainActor [weak self] in
                            guard let self, self.screenshotUploadRequestID == uploadID else { return }
                            self.screenshotUploadActivity = AIActivity(
                                startedAt: startedAt,
                                message: L(
                                    "Uploading %1$@ · %2$@ (%3$d/%4$d)…",
                                    locale,
                                    slotPlan.slot.displayName,
                                    index + 1,
                                    total
                                )
                            )
                        }
                    }
                )
            }

            if localeUploadCount > 0 {
                return .success(locale: locale, count: localeUploadCount)
            } else {
                return .skipped(locale: locale)
            }
        } catch {
            return .failure(
                locale: locale,
                error: error.localizedDescription,
                hadRemoteContent: replacedSlotWithRemoteContent
            )
        }
    }

    /// Carry custom screenshot order over to a rescanned or re-matched set.
    /// Order is keyed by coverage locale — the key the grid and
    /// `moveScreenshotAsset` use — so locales showing shared or remapped
    /// screenshots keep their order instead of silently reverting to filename
    /// order.
    internal func reconcileScreenshotOrder() {
        var next: [String: [String]] = [:]
        for group in screenshotCoverageGroups {
            for (slot, assets) in Dictionary(grouping: group.assets, by: \.deviceSlot) {
                let key = screenshotOrderKey(locale: group.locale, slot: slot)
                guard let previous = screenshotOrderByGroup[key] else { continue }
                let currentIDs = Set(assets.map(\.id))
                let preserved = previous.filter { currentIDs.contains($0) }
                let preservedIDs = Set(preserved)
                let newIDs = assets
                    .sorted(by: screenshotAssetSort)
                    .map(\.id)
                    .filter { !preservedIDs.contains($0) }
                next[key] = preserved + newIDs
            }
        }
        screenshotOrderByGroup = next
    }

    internal func screenshotOrderKey(locale: String, slot: ScreenshotDeviceSlot?) -> String {
        "\(locale)|\(slot?.rawValue ?? "unsupported")"
    }

    internal func screenshotAssetSort(_ lhs: ScreenshotAsset, _ rhs: ScreenshotAsset) -> Bool {
        lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }

    func presentScreenshotPicker() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Import")
        panel.message = L("Select a screenshot folder.")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in self.loadScreenshotsFolder(url) }
        }
        #endif
    }

    internal static func loadScreenshotIPadSupportOverrides(defaults: UserDefaults = .standard) -> [String: ScreenshotIPadSupportOverride] {
        guard let stored = defaults.dictionary(forKey: SettingsKey.screenshotIPadSupportOverrides) as? [String: String] else {
            return [:]
        }
        return stored.reduce(into: [:]) { result, pair in
            if let override = ScreenshotIPadSupportOverride(rawValue: pair.value) {
                result[pair.key] = override
            }
        }
    }

    internal func persistScreenshotIPadSupportOverrides() {
        let stored = screenshotIPadSupportOverrides.mapValues(\.rawValue)
        defaults.set(stored, forKey: SettingsKey.screenshotIPadSupportOverrides)
    }

    internal func selectedScreenshotPlatformContains(_ needle: String) -> Bool {
        selectedScreenshotPlatform.contains(needle)
    }

    func setScreenshotIPadSupportOverride(_ override: ScreenshotIPadSupportOverride) {
        guard let key = selectedScreenshotRequirementKey else { return }
        if override == .automatic {
            screenshotIPadSupportOverrides.removeValue(forKey: key)
        } else {
            screenshotIPadSupportOverrides[key] = override
        }
        persistScreenshotIPadSupportOverrides()
    }


    // MARK: - View State Computations

    var missingRequirementsByLocale: [String: [ScreenshotSlotRequirement]] {
        getScreenshotIssuesCache()?.missingRequirementsByLocale ?? [:]
    }

    var screenshotPreviewControlsState: ScreenshotPreviewControlsState {
        if isUsingMockData || appStoreService == nil {
            let reason = L("Connect App Store Connect before uploading screenshots.")
            return ScreenshotPreviewControlsState(selectedDisabledReason: reason, allDisabledReason: reason)
        }
        if isUploadingScreenshots || isPreparingScreenshotReplacement {
            let reason = L("Screenshot upload is already in progress.")
            return ScreenshotPreviewControlsState(selectedDisabledReason: reason, allDisabledReason: reason)
        }
        if selectedVersion?.canEditMetadata != true {
            let reason = L("This version's metadata is locked.")
            return ScreenshotPreviewControlsState(selectedDisabledReason: reason, allDisabledReason: reason)
        }
        guard screenshotScan != nil else {
            let reason = L("No screenshots imported.")
            return ScreenshotPreviewControlsState(selectedDisabledReason: reason, allDisabledReason: reason)
        }

        let groups = screenshotCoverageGroups
        let issues = screenshotIssues
        let slots = Set(uploadableScreenshotSlots)

        let selectedReason: String? = {
            guard let selectedGroup = selectedScreenshotGroup, !selectedGroup.isUnassigned else {
                return L("Select a screenshot locale first.")
            }
            if hasBlockingScreenshotIssue(locale: selectedGroup.locale, issues: issues) {
                return L("%@ has blocking screenshot issues.", selectedGroup.locale)
            }
            if !hasUploadableScreenshots(selectedGroup.assets, slots: slots) {
                return L("%@ has no ready screenshots to upload.", selectedGroup.locale)
            }
            return nil
        }()

        let hasPreviewableLocale = groups.contains { group in
            !group.isUnassigned
                && !hasBlockingScreenshotIssue(locale: group.locale, issues: issues)
                && hasUploadableScreenshots(group.assets, slots: slots)
        }
        let allReason: String? = hasPreviewableLocale
            ? nil
            : (screenshotBlockingIssueCount > 0
                ? L("Every uploadable locale has blocking screenshot issues.")
                : L("No uploadable screenshots found."))

        return ScreenshotPreviewControlsState(
            selectedDisabledReason: selectedReason,
            allDisabledReason: allReason
        )
    }

    internal func hasBlockingScreenshotIssue(locale: String, issues: [ScreenshotIssue]) -> Bool {
        issues.contains { $0.locale == locale && $0.severity == .error }
    }


}
