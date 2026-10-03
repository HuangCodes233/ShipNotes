import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
extension AppState {
    func loadScreenshotsFolder(_ url: URL) {
        // The scan walks the directory tree and SHA256-hashes every image
        // (reading each multi-MB file). Running that synchronously on the main
        // actor freezes the UI on real screenshot folders, so we hand the
        // heavy work to a detached task and only touch state back on the main
        // actor once it's done.
        screenshotScanTask?.cancel()
        let requestID = UUID()
        screenshotScanRequestID = requestID
        isScanningScreenshots = true
        let requirementKey = selectedScreenshotRequirementKey
        screenshotScanTask = Task {
            defer {
                if screenshotScanRequestID == requestID {
                    isScanningScreenshots = false
                    screenshotScanTask = nil
                }
            }
            do {
                let work = Task.detached(priority: .userInitiated) {
                    let scan = try ScreenshotScanner().scan(url: url)
                    let detection =
                        requirementKey != nil
                        ? ScreenshotIPadSupportDetector.detect(from: url)
                        : nil
                    return (scan, detection)
                }
                // A detached task doesn't inherit cancellation: forward it, so
                // Refresh or a new folder stops the previous walk and hashing.
                let (scan, detection) = try await withTaskCancellationHandler {
                    try await work.value
                } onCancel: {
                    work.cancel()
                }
                guard screenshotScanRequestID == requestID else { return }

                let previousLocale = selectedScreenshotLocale
                screenshotFolder = url
                screenshotScan = scan
                selectedScreenshotAssetId = nil
                screenshotFocusTargetID = nil
                screenshotUploadSummary = nil
                pendingScreenshotReplacement = nil
                screenshotAISharedAssetIDs = []
                screenshotAILocaleOverrides = [:]
                screenshotCoverageGroupsCache = nil
                screenshotIssuesCache = nil
                if let key = requirementKey, let detection {
                    screenshotIPadSupportDetections[key] = detection
                }
                // Keep the selected locale across a refresh; otherwise pick the
                // first coverage group (a version locale, not the raw folder
                // guess, so toolbar actions target the group on screen).
                let groups = screenshotCoverageGroups
                selectedScreenshotLocale =
                    groups.contains { $0.locale == previousLocale }
                    ? previousLocale
                    : (groups.first { !$0.isUnassigned } ?? groups.first)?.locale
                reconcileScreenshotOrder()
                refreshRemoteScreenshotCountsIfNeeded()
                lastError = nil
            } catch {
                guard screenshotScanRequestID == requestID else { return }
                handleError(error)
            }
        }
    }

    func askAIToClassifyScreenshots() {
        Task { await classifyScreenshotsWithAI() }
    }

    func classifyScreenshotsWithAI() async {
        guard visionAIService.isConfigured else {
            setError(L("Configure a vision AI model in Settings before matching screenshots."))
            return
        }
        let assets = screenshotAssetsForAIClassification
        guard !assets.isEmpty else {
            setError(L("No screenshots need AI matching."))
            return
        }

        isAIRunning = true
        aiActivity = AIActivity(startedAt: Date(), message: L("AI is matching screenshots…"))
        defer {
            isAIRunning = false
            aiActivity = nil
        }

        // Results apply to the scan they were computed for: switching apps or
        // rescanning mid-run discards them.
        let scanRequestID = screenshotScanRequestID
        let requestedAppId = selectedAppId
        let knownLocales = screenshotKnownLocalesForAI()
        let appName = selectedApp?.name
        let batchSize = 12
        let batches = stride(from: 0, to: assets.count, by: batchSize).map {
            Array(assets[$0..<min($0 + batchSize, assets.count)])
        }

        var assignments: [ScreenshotLocaleAssignment] = []
        var failure: Error?
        for (index, batch) in batches.enumerated() {
            if batches.count > 1 {
                aiActivity = AIActivity(
                    startedAt: Date(),
                    message: L("AI is matching screenshots (%1$d / %2$d)…", index + 1, batches.count)
                )
            }
            do {
                assignments += try await visionAIService.classifyScreenshotLocales(
                    assets: batch,
                    knownLocales: knownLocales,
                    appName: appName
                )
                bumpAICallCount()
            } catch {
                // Keep what earlier (already paid-for) batches returned.
                failure = error
                break
            }
            guard screenshotScanRequestID == scanRequestID, selectedAppId == requestedAppId else { return }
        }
        guard screenshotScanRequestID == scanRequestID, selectedAppId == requestedAppId else { return }

        let applied = applyScreenshotLocaleAssignments(
            assignments,
            candidateAssetIDs: Set(assets.map(\.id))
        )
        if applied > 0 {
            screenshotUploadSummary = L(
                "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", applied)
        } else if failure == nil {
            screenshotUploadSummary = L("AI did not find any screenshot locale matches.")
        }
        if let failure {
            handleError(failure)
        } else {
            lastError = nil
        }
    }

    func screenshotAssets(locale: String, slot: ScreenshotDeviceSlot?) -> [ScreenshotAsset] {
        let assets = effectiveScreenshotAssets(locale: locale).filter { $0.deviceSlot == slot }
        return orderedScreenshotAssets(assets, locale: locale, slot: slot)
    }

    func orderedScreenshotAssets(
        _ assets: [ScreenshotAsset],
        locale: String,
        slot: ScreenshotDeviceSlot?
    ) -> [ScreenshotAsset] {
        let key = screenshotOrderKey(locale: locale, slot: slot)
        guard let order = screenshotOrderByGroup[key] else {
            return assets.sorted(by: screenshotAssetSort)
        }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return assets.sorted { lhs, rhs in
            let lhsIndex = position[lhs.id] ?? Int.max
            let rhsIndex = position[rhs.id] ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return screenshotAssetSort(lhs, rhs)
        }
    }

    func effectiveScreenshotAssets(locale: String) -> [ScreenshotAsset] {
        guard let scan = screenshotScan else { return [] }
        if let group = screenshotCoverageGroups.first(where: { !$0.isUnassigned && $0.locale == locale }) {
            return group.assets
        }
        // Preserve queries for locales outside the currently displayed coverage.
        let directAssets = scan.assets.filter { canonicalScreenshotLocale(for: $0) == locale }
        var assets = directAssets
        if let language = sharedScreenshotLanguage(for: locale) {
            let directSlots = Set(directAssets.compactMap(\.deviceSlot))
            let sharedAssets = scan.assets.filter { asset in
                guard let assetLocale = canonicalScreenshotLocale(for: asset),
                    languageCode(for: assetLocale) == language,
                    screenshotAISharedAssetIDs.contains(asset.id)
                        || screenshotAsset(asset, hasGenericLanguageHint: language)
                else {
                    return false
                }
                if let slot = asset.deviceSlot, directSlots.contains(slot) {
                    return false
                }
                return true
            }
            assets.append(contentsOf: sharedAssets)
        }
        return uniqueScreenshotAssets(assets)
    }

    func screenshotCoverageGroupsCacheKey(
        scan: ScreenshotScan,
        locales: [String]
    ) -> ScreenshotCoverageGroupsCacheKey {
        ScreenshotCoverageGroupsCacheKey(
            locales: locales,
            assets: scan.assets,
            localeOverrides: screenshotAILocaleOverrides,
            sharedAssetIDs: screenshotAISharedAssetIDs
        )
    }

    func makeScreenshotCoverage(
        scan: ScreenshotScan,
        locales: [String]
    ) -> (groups: [ScreenshotLocaleGroup], localeByAssetID: [String: String?]) {
        // Resolve each path once per rebuild instead of once for every locale
        // and again for every missing-slot query.
        var directByLocale: [String: [ScreenshotAsset]] = [:]
        var sharedByLanguage: [String: [ScreenshotAsset]] = [:]
        var unassignedAssets: [ScreenshotAsset] = []
        var localeByAssetID: [String: String?] = [:]
        localeByAssetID.reserveCapacity(scan.assets.count)
        for asset in scan.assets {
            let resolved = canonicalScreenshotLocale(for: asset, allowedLocales: locales)
            localeByAssetID[asset.id] = .some(resolved)
            guard let locale = resolved else {
                unassignedAssets.append(asset)
                continue
            }
            directByLocale[locale, default: []].append(asset)
            if let language = sharedScreenshotLanguage(for: locale),
                screenshotAISharedAssetIDs.contains(asset.id)
                    || screenshotAsset(asset, hasGenericLanguageHint: language)
            {
                sharedByLanguage[language, default: []].append(asset)
            }
        }

        var groups: [ScreenshotLocaleGroup] = []
        groups.reserveCapacity(locales.count + 1)
        for locale in locales {
            let directAssets = directByLocale[locale] ?? []
            var assets = directAssets
            if let language = sharedScreenshotLanguage(for: locale) {
                let directSlots = Set(directAssets.compactMap(\.deviceSlot))
                for asset in sharedByLanguage[language] ?? [] {
                    if let slot = asset.deviceSlot, directSlots.contains(slot) { continue }
                    assets.append(asset)
                }
            }
            groups.append(
                ScreenshotLocaleGroup(locale: locale, assets: uniqueScreenshotAssets(assets), isUnassigned: false))
        }

        if !unassignedAssets.isEmpty {
            groups.append(
                ScreenshotLocaleGroup(
                    locale: ScreenshotScan.unassignedLocaleDisplayName,
                    assets: unassignedAssets.sorted(by: screenshotAssetSort),
                    isUnassigned: true
                ))
        } else if let unassigned = scan.localeGroups.first(where: { $0.isUnassigned }) {
            groups.append(unassigned)
        }
        return (groups, localeByAssetID)
    }

    private func canonicalScreenshotLocale(_ rawLocale: String?, allowedLocales: [String]) -> String? {
        guard let rawLocale else { return nil }
        if allowedLocales.isEmpty {
            return normalizedScreenshotLocale(rawLocale).nilIfEmpty
        }
        return resolveScreenshotLocale(rawLocale, allowedLocales: allowedLocales)
    }

    func canonicalScreenshotLocale(for asset: ScreenshotAsset) -> String? {
        // Reading the coverage groups refreshes the cache when inputs changed.
        _ = screenshotCoverageGroups
        if let cached = screenshotCoverageGroupsCache?.localeByAssetID[asset.id] {
            return cached
        }
        return canonicalScreenshotLocale(for: asset, allowedLocales: screenshotCoverageLocales)
    }

    private func canonicalScreenshotLocale(for asset: ScreenshotAsset, allowedLocales: [String]) -> String? {
        if let override = screenshotAILocaleOverrides[asset.id] {
            return canonicalScreenshotLocale(override, allowedLocales: allowedLocales)
        }
        return explicitScreenshotLocale(from: asset.relativePath, allowedLocales: allowedLocales)
            ?? canonicalScreenshotLocale(asset.locale, allowedLocales: allowedLocales)
    }

    private func explicitScreenshotLocale(from relativePath: String, allowedLocales: [String]) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        for token in LocaleMapper.pathLocaleHints(components) {
            if allowedLocales.isEmpty {
                if let mapped = LocaleMapper().resolve(token) {
                    return mapped
                }
            } else if let mapped = resolveScreenshotLocale(token, allowedLocales: allowedLocales) {
                return mapped
            }
        }
        return nil
    }

    func resolveScreenshotLocale(_ rawLocale: String, allowedLocales: [String]) -> String? {
        let normalized = normalizedScreenshotLocale(rawLocale)
        guard !normalized.isEmpty else { return nil }
        let allowed = Set(allowedLocales)
        if allowed.contains(normalized) { return normalized }

        let mapper = LocaleMapper()
        if let mapped = mapper.resolve(normalized), allowed.contains(mapped) {
            return mapped
        }

        guard let language = languageCode(for: normalized) else { return nil }
        if let defaultLocale = sharedScreenshotLanguageDefaults[language],
            allowed.contains(defaultLocale)
        {
            return defaultLocale
        }

        let sameLanguageLocales = allowedLocales.filter { languageCode(for: $0) == language }
        if sameLanguageLocales.count == 1 {
            return sameLanguageLocales[0]
        }
        return nil
    }

    func normalizedScreenshotLocale(_ rawLocale: String) -> String {
        let cleaned =
            rawLocale
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        let parts =
            cleaned
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        guard let language = parts.first?.lowercased() else { return "" }
        guard parts.count > 1 else { return language }
        let regionParts = parts.dropFirst().map { part in
            part.count == 4
                ? part.prefix(1).uppercased() + part.dropFirst().lowercased()
                : part.uppercased()
        }
        return ([language] + regionParts).joined(separator: "-")
    }

    func languageCode(for locale: String) -> String? {
        normalizedScreenshotLocale(locale)
            .split(separator: "-")
            .first
            .map { String($0).lowercased() }
    }

    func uniqueLocales(_ locales: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for locale in locales {
            let normalized = normalizedScreenshotLocale(locale)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    func sharedScreenshotLanguage(for locale: String) -> String? {
        let language = locale.split(separator: "-").first.map(String.init)?.lowercased() ?? locale.lowercased()
        guard sharedScreenshotLanguageDefaults[language] != nil else { return nil }
        return language
    }

    func screenshotAsset(_ asset: ScreenshotAsset, hasGenericLanguageHint language: String) -> Bool {
        let pathParts = asset.relativePath
            .split(separator: "/")
            .dropLast()
            .map { $0.lowercased() }
        if pathParts.contains(language) {
            return true
        }

        let lastPathComponent = (asset.relativePath as NSString).lastPathComponent
        let baseName = (lastPathComponent as NSString)
            .deletingPathExtension
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let separators = CharacterSet(charactersIn: " -./()[]")
        return baseName.components(separatedBy: separators).contains(language)
    }

    func uniqueScreenshotAssets(_ assets: [ScreenshotAsset]) -> [ScreenshotAsset] {
        var seen = Set<String>()
        var result: [ScreenshotAsset] = []
        for asset in assets where seen.insert(asset.id).inserted {
            result.append(asset)
        }
        return result
    }

    func screenshotKnownLocalesForAI() -> [String] {
        let locales = screenshotCoverageLocales
        return locales.isEmpty ? LocaleMapper.appStoreLocales : locales
    }

    func applyScreenshotLocaleAssignments(
        _ assignments: [ScreenshotLocaleAssignment],
        candidateAssetIDs: Set<String>
    ) -> Int {
        guard let scan = screenshotScan else { return 0 }
        let allowed = Set(screenshotKnownLocalesForAI())
        var resolvedByAssetID: [String: String] = [:]
        for assignment in assignments where resolvedByAssetID[assignment.assetID] == nil {
            if let locale = resolveAIScreenshotLocale(assignment.locale, allowed: allowed) {
                resolvedByAssetID[assignment.assetID] = locale
            }
        }
        guard !resolvedByAssetID.isEmpty else { return 0 }

        func assignmentCountKey(locale: String, slot: ScreenshotDeviceSlot) -> String {
            "\(locale)|\(slot.rawValue)"
        }

        // Resolve every asset once, before any override changes. An asset's
        // canonical locale depends only on its own override, and resolving
        // inside the loop below would rebuild the coverage cache after each
        // assignment.
        let localeByAssetID = Dictionary(
            scan.assets.map { ($0.id, canonicalScreenshotLocale(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )

        var assignedCounts: [String: Int] = [:]
        for asset in scan.assets {
            guard asset.status == .ready,
                let locale = localeByAssetID[asset.id] ?? nil,
                let slot = asset.deviceSlot
            else {
                continue
            }
            assignedCounts[assignmentCountKey(locale: locale, slot: slot), default: 0] += 1
        }

        var changedCount = 0
        var firstChangedLocale: String?
        let updatedAssets = scan.assets.map { asset in
            guard candidateAssetIDs.contains(asset.id),
                let locale = resolvedByAssetID[asset.id],
                let slot = asset.deviceSlot,
                (localeByAssetID[asset.id] ?? nil) != locale,
                shouldApplyAIScreenshotAssignment(
                    asset,
                    to: locale,
                    assignedCount: assignedCounts[assignmentCountKey(locale: locale, slot: slot), default: 0]
                )
            else {
                return asset
            }
            changedCount += 1
            let assignmentKey = assignmentCountKey(locale: locale, slot: slot)
            assignedCounts[assignmentKey, default: 0] += 1
            rememberAIScreenshotAssignment(
                asset,
                locale: locale,
                wasUnassigned: (localeByAssetID[asset.id] ?? nil) == nil
            )
            if firstChangedLocale == nil {
                firstChangedLocale = locale
            }
            return ScreenshotAsset(
                url: asset.url,
                relativePath: asset.relativePath,
                size: asset.size,
                locale: locale,
                deviceSlot: asset.deviceSlot,
                status: asset.status,
                contentHash: asset.contentHash
            )
        }

        guard changedCount > 0 else { return 0 }
        let updatedScan = ScreenshotScan(
            inputRoot: scan.inputRoot,
            root: scan.root,
            sourceKind: scan.sourceKind,
            assets: updatedAssets,
            skippedCount: scan.skippedCount
        )
        screenshotScan = updatedScan
        screenshotCoverageGroupsCache = nil
        screenshotIssuesCache = nil
        if selectedScreenshotLocale == ScreenshotScan.unassignedLocaleDisplayName,
            let firstChangedLocale
        {
            selectedScreenshotLocale = firstChangedLocale
        }
        reconcileScreenshotOrder()
        return changedCount
    }

    func shouldApplyAIScreenshotAssignment(_ asset: ScreenshotAsset, to locale: String, assignedCount: Int) -> Bool {
        guard asset.status == .ready, asset.deviceSlot != nil else { return false }
        return assignedCount < 10
    }

    func rememberAIScreenshotAssignment(_ asset: ScreenshotAsset, locale: String, wasUnassigned: Bool) {
        screenshotAILocaleOverrides[asset.id] = locale
        if wasUnassigned, sharedScreenshotLanguage(for: locale) != nil {
            screenshotAISharedAssetIDs.insert(asset.id)
        }
    }

    func resolveAIScreenshotLocale(_ rawLocale: String, allowed: Set<String>) -> String? {
        resolveScreenshotLocale(
            rawLocale,
            allowedLocales: allowed.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            })
    }

    func missingScreenshotRequirements(locale: String) -> [ScreenshotSlotRequirement] {
        guard locale != ScreenshotScan.unassignedLocaleDisplayName else { return [] }
        if let missing = getScreenshotIssuesCache()?.missingRequirementsByLocale[locale] {
            return missing
        }
        let assets = effectiveScreenshotAssets(locale: locale)
        return requiredScreenshotSlotGroups.filter { requirement in
            !requirement.isSatisfied(by: assets)
        }
    }

    func moveScreenshotAsset(_ asset: ScreenshotAsset, locale: String, direction: ScreenshotMoveDirection) {
        let slot = asset.deviceSlot
        let key = screenshotOrderKey(locale: locale, slot: slot)
        var orderedIDs = screenshotAssets(locale: locale, slot: slot).map(\.id)
        guard let index = orderedIDs.firstIndex(of: asset.id) else { return }
        let target: Int
        switch direction {
        case .up: target = orderedIDs.index(before: index)
        case .down: target = orderedIDs.index(after: index)
        }
        guard orderedIDs.indices.contains(target) else { return }
        orderedIDs.swapAt(index, target)
        screenshotOrderByGroup[key] = orderedIDs
    }

}
