import Foundation

@MainActor
extension AppState {
    /// The group the screenshot workspace shows: the selected locale, or the
    /// first group when the selection isn't (or is no longer) a coverage
    /// locale. Toolbar actions and the workspace must agree on this.
    var selectedScreenshotGroup: ScreenshotLocaleGroup? {
        let groups = screenshotCoverageGroups
        return groups.first { $0.locale == selectedScreenshotLocale } ?? groups.first
    }

    var requiredScreenshotSlotGroups: [ScreenshotSlotRequirement] {
        ScreenshotSlotRequirement.groups(
            platform: selectedScreenshotPlatform,
            requiresIPad: screenshotRequiresIPad
        )
    }

    var expectedScreenshotSlots: [ScreenshotDeviceSlot] {
        var slots: [ScreenshotDeviceSlot] = []
        for requirement in requiredScreenshotSlotGroups {
            for slot in requirement.slots where !slots.contains(slot) {
                slots.append(slot)
            }
        }
        return slots
    }

    var visibleScreenshotSlots: [ScreenshotDeviceSlot] {
        getScreenshotIssuesCache()?.visibleScreenshotSlots ?? expectedScreenshotSlots
    }

    var uploadableScreenshotSlots: [ScreenshotDeviceSlot] {
        visibleScreenshotSlots.filter { slot in
            slot != .iPad13 || screenshotRequiresIPad
        }
    }

    var canConfigureScreenshotIPadSupport: Bool {
        !selectedScreenshotPlatformContains("mac")
            && !selectedScreenshotPlatformContains("tv")
            && !selectedScreenshotPlatformContains("vision")
            && !selectedScreenshotPlatformContains("watch")
    }

    var screenshotIPadSupportOverride: ScreenshotIPadSupportOverride {
        guard let key = selectedScreenshotRequirementKey else { return .automatic }
        return screenshotIPadSupportOverrides[key] ?? .automatic
    }

    var selectedScreenshotIPadSupportDetection: ScreenshotIPadSupportDetection {
        guard let key = selectedScreenshotRequirementKey else { return .unknown }
        return screenshotIPadSupportDetections[key] ?? .unknown
    }

    var screenshotRequiresIPad: Bool {
        guard canConfigureScreenshotIPadSupport else { return false }
        switch screenshotIPadSupportOverride {
        case .automatic:
            return selectedScreenshotIPadSupportDetection.supportsIPad == true
        case .required:
            return true
        case .ignored:
            return false
        }
    }

    var screenshotIPadRequirementSummary: String {
        guard canConfigureScreenshotIPadSupport else {
            return L("iPad screenshots are not used for this platform.")
        }
        switch screenshotIPadSupportOverride {
        case .automatic:
            switch selectedScreenshotIPadSupportDetection {
            case .supported:
                return L("Auto detected: iPad 13\" screenshots are required.")
            case .unsupported:
                return L("Auto detected: iPad screenshots are ignored.")
            case .unknown:
                return L("Auto detection is unknown. iPad screenshots are ignored for now.")
            }
        case .required:
            return L("Manual setting: iPad 13\" screenshots are required.")
        case .ignored:
            return L("Manual setting: iPad screenshots are ignored.")
        }
    }

    var selectedScreenshotRequirementKey: String? {
        selectedApp?.id ?? selectedAppId ?? selectedApp?.bundleId
    }

    var selectedScreenshotPlatform: String {
        (selectedVersion?.platform ?? selectedApp?.platform ?? "").lowercased()
    }

    func getScreenshotIssuesCache() -> ScreenshotIssuesCache? {
        guard let scan = screenshotScan else {
            screenshotIssuesCache = nil
            return nil
        }
        let groups = screenshotCoverageGroups
        let requiredGroups = requiredScreenshotSlotGroups
        guard let coverageKey = screenshotCoverageGroupsCache?.key else {
            return nil
        }
        let key = ScreenshotIssuesCacheKey(
            coverageKey: coverageKey,
            requiredGroups: requiredGroups
        )
        if let cache = screenshotIssuesCache, cache.key == key {
            return cache
        }
        let issues = scan.issues(requiredGroups: requiredGroups, localeGroups: groups)
        let blocking = issues.filter { $0.severity == .error }.count
        let warning = issues.filter { $0.severity == .warning }.count

        var missing: [String: [ScreenshotSlotRequirement]] = [:]
        missing.reserveCapacity(groups.count)
        for group in groups where !group.isUnassigned {
            missing[group.locale] = requiredGroups.filter { requirement in
                !requirement.isSatisfied(by: group.assets)
            }
        }

        var slots = requiredGroups.flatMap { $0.slots }
        for asset in scan.assets {
            guard let slot = asset.deviceSlot, !slots.contains(slot) else { continue }
            slots.append(slot)
        }

        let cache = ScreenshotIssuesCache(
            key: key,
            issues: issues,
            blockingIssueCount: blocking,
            warningCount: warning,
            missingRequirementsByLocale: missing,
            visibleScreenshotSlots: slots,
            aiClassificationCandidates: makeScreenshotAIClassificationCandidates(
                scan: scan,
                groups: groups,
                missingRequirementsByLocale: missing
            )
        )
        screenshotIssuesCache = cache
        return cache
    }

    var screenshotCoverageGroups: [ScreenshotLocaleGroup] {
        guard let scan = screenshotScan else {
            screenshotCoverageGroupsCache = nil
            return []
        }
        let locales = screenshotCoverageLocales
        let key = screenshotCoverageGroupsCacheKey(scan: scan, locales: locales)
        if let cache = screenshotCoverageGroupsCache, cache.key == key {
            return cache.groups
        }
        let coverage = makeScreenshotCoverage(scan: scan, locales: locales)
        screenshotCoverageGroupsCache = ScreenshotCoverageGroupsCache(
            key: key,
            groups: coverage.groups,
            localeByAssetID: coverage.localeByAssetID
        )
        return coverage.groups
    }

    var screenshotIssues: [ScreenshotIssue] {
        getScreenshotIssuesCache()?.issues ?? []
    }

    var screenshotBlockingIssueCount: Int {
        getScreenshotIssuesCache()?.blockingIssueCount ?? 0
    }

    var screenshotWarningCount: Int {
        getScreenshotIssuesCache()?.warningCount ?? 0
    }

    var screenshotReadyForSubmission: Bool {
        screenshotScan != nil && screenshotBlockingIssueCount == 0
    }

    var screenshotChecklistLabel: String {
        guard screenshotScan != nil else {
            return L("Screenshots not checked in ShipNotes")
        }
        if screenshotBlockingIssueCount == 0 {
            if screenshotWarningCount == 0 {
                return L("Screenshots ready")
            }
            return L("Screenshots ready with %d warning(s)", screenshotWarningCount)
        }
        return L("Screenshots have %d blocking issue(s)", screenshotBlockingIssueCount)
    }

    var canUploadSelectedScreenshots: Bool {
        screenshotSelectedPreviewDisabledReason == nil
    }

    var screenshotSelectedPreviewDisabledReason: String? {
        screenshotPreviewControlsState.selectedDisabledReason
    }

    var canUploadAllScreenshots: Bool {
        screenshotAllPreviewDisabledReason == nil
    }

    var screenshotAllPreviewDisabledReason: String? {
        screenshotPreviewControlsState.allDisabledReason
    }

    var screenshotAIClassificationHelp: String {
        guard screenshotScan != nil else {
            return L("Import screenshots before using AI matching.")
        }
        guard isVisionAIConfigured else {
            return L("Configure a vision AI model in Settings before matching screenshots.")
        }
        guard !screenshotAssetsForAIClassification.isEmpty else {
            return L("No screenshots need AI matching.")
        }
        return L(
            "Use the configured vision AI model to match unclear or missing-language screenshots to App Store locales.")
    }

    var canClassifyScreenshotsWithAI: Bool {
        screenshotScan != nil
            && isVisionAIConfigured
            && !isAIRunning
            && !screenshotAssetsForAIClassification.isEmpty
    }

    var screenshotKnownVersionLocales: [String] {
        let releaseNoteLocales = uniqueLocales(localeNotes.map(\.locale))
        if !releaseNoteLocales.isEmpty {
            return releaseNoteLocales
        }

        let storeCopyLocales = uniqueLocales(storeCopyLocales.map(\.locale))
        if !storeCopyLocales.isEmpty {
            return storeCopyLocales
        }

        return uniqueLocales(remoteNotesByLocale.keys.sorted())
    }

    var screenshotCoverageLocales: [String] {
        let versionLocales = screenshotKnownVersionLocales
        if !versionLocales.isEmpty {
            return versionLocales
        }
        return uniqueLocales(
            screenshotScan?.localeGroups.compactMap { $0.isUnassigned ? nil : $0.locale } ?? []
        )
    }

    var screenshotAssetsForAIClassification: [ScreenshotAsset] {
        getScreenshotIssuesCache()?.aiClassificationCandidates ?? []
    }

    /// Unassigned screenshots, plus assigned ones that could fill a gap: a
    /// sibling locale of the same language misses a required size in exactly
    /// this screenshot's slot (AI may find it belongs there). Reassigning a
    /// screenshot of any other slot can't satisfy the requirement, and
    /// including those turned a missing iPad set into "send every iPhone
    /// screenshot to the vision model".
    private func makeScreenshotAIClassificationCandidates(
        scan: ScreenshotScan,
        groups: [ScreenshotLocaleGroup],
        missingRequirementsByLocale: [String: [ScreenshotSlotRequirement]]
    ) -> [ScreenshotAsset] {
        let localeByAssetID = screenshotCoverageGroupsCache?.localeByAssetID ?? [:]
        func locale(of asset: ScreenshotAsset) -> String? {
            if let cached = localeByAssetID[asset.id] { return cached }
            return canonicalScreenshotLocale(for: asset)
        }

        let classifiable = scan.assets.filter { $0.deviceSlot != nil && $0.status == .ready }
        var candidates = classifiable.filter { locale(of: $0) == nil }

        var missingSlotsByLanguage: [String: Set<ScreenshotDeviceSlot>] = [:]
        for group in groups where !group.isUnassigned {
            guard let missing = missingRequirementsByLocale[group.locale], !missing.isEmpty,
                let language = languageCode(for: group.locale)
            else { continue }
            missingSlotsByLanguage[language, default: []].formUnion(missing.flatMap(\.slots))
        }

        if !missingSlotsByLanguage.isEmpty {
            candidates.append(
                contentsOf: classifiable.filter { asset in
                    guard let slot = asset.deviceSlot,
                        let assetLocale = locale(of: asset),
                        let language = languageCode(for: assetLocale)
                    else {
                        return false
                    }
                    return missingSlotsByLanguage[language]?.contains(slot) == true
                })
        }

        return uniqueScreenshotAssets(candidates)
    }
}

let sharedScreenshotLanguageDefaults: [String: String] = [
    "en": "en-US",
    "es": "es-ES",
    "fr": "fr-FR",
    "pt": "pt-BR",
]
