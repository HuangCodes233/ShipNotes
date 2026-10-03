import Foundation
@testable import ShipNotes

// Shared test doubles. Keep protocol fakes here so suites do not bury mocks
// inside a single feature file.

final class MockASCService: AppStoreConnectServicing, @unchecked Sendable {
    var builds: [Build] = []
    var allBuildsByApp: [String: [Build]] = [:]
    var fetchAllBuildsDelayNanosecondsByApp: [String: UInt64] = [:]
    var attachedBuild: Build?
    var lastAttachedBuildId: String? = "unset"
    var fetchedApps: [AppRecord] = []
    var fetchedVersions: [ReleaseVersion] = []
    var fetchedVersionsByApp: [String: [ReleaseVersion]] = [:]
    var fetchedLocalizations: [RemoteLocaleNote] = []
    var fetchedLocalizationsByVersion: [String: [RemoteLocaleNote]] = [:]
    var fetchLocalizationDelayNanosecondsByVersion: [String: UInt64] = [:]
    var fetchAttachedBuildCallCount = 0
    var createLocalizationError: Error?
    var createLocalizationCallCount = 0
    var updateWhatsNewError: Error?
    var updateStoreMetadataError: Error?
    var updateStoreMetadataFieldError: Error?
    var fetchScreenshotSetsError: Error?
    var replaceScreenshotsError: Error?
    var fetchLocalizationsCallCount = 0
    var lastUpdatedWhatsNew: (localizationId: String, text: String)?
    var updateWhatsNewDelayNanoseconds: UInt64 = 0
    var lastUpdatedStoreMetadata: StoreMetadataFields?
    var versionOnlyMetadataResponse = false
    var lastUpdatedStoreMetadataField: (field: StoreCopyField, value: String)?
    var remoteScreenshotSets: [String: [RemoteScreenshotSet]] = [:]
    var fetchScreenshotSetDelayNanoseconds: [String: UInt64] = [:]
    var replacedScreenshots: [(localizationId: String, displayType: String, fileNames: [String])] = []

    func validateCredentials() async throws {}
    func fetchApps() async throws -> [AppRecord] { fetchedApps }
    func fetchVersions(appId: String) async throws -> [ReleaseVersion] {
        fetchedVersionsByApp[appId] ?? fetchedVersions
    }
    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote] {
        fetchLocalizationsCallCount += 1
        if let delay = fetchLocalizationDelayNanosecondsByVersion[versionId], delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return fetchedLocalizationsByVersion[versionId] ?? fetchedLocalizations
    }
    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote {
        if let updateWhatsNewError {
            throw updateWhatsNewError
        }
        if updateWhatsNewDelayNanoseconds > 0 {
            // `try`, not `try?` — a real request throws on cancellation, and the
            // cancel path depends on that propagating.
            try await Task.sleep(nanoseconds: updateWhatsNewDelayNanoseconds)
        }
        lastUpdatedWhatsNew = (localizationId, text)
        let locale = fetchedLocalizations.first { $0.localizationId == localizationId }?.locale ?? "en-US"
        let metadata = fetchedLocalizations.first { $0.localizationId == localizationId }?.storeMetadata ?? .empty
        return RemoteLocaleNote(localizationId: localizationId, locale: locale, text: text, storeMetadata: metadata)
    }
    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote {
        if let updateStoreMetadataError {
            throw updateStoreMetadataError
        }
        lastUpdatedStoreMetadata = metadata
        var returned = metadata
        // Simulate Apple's response for this endpoint: version-localization
        // fields (incl. subtitle) are echoed back, but app-info–level fields
        // like privacyPolicyURL never appear.
        if versionOnlyMetadataResponse {
            returned.privacyPolicyURL = ""
        }
        let remote = fetchedLocalizations.first { $0.localizationId == localizationId }
        return RemoteLocaleNote(
            localizationId: localizationId,
            locale: remote?.locale ?? "en-US",
            text: remote?.text ?? "",
            storeMetadata: returned
        )
    }
    func updateStoreMetadataField(
        localizationId: String, field: StoreCopyField, value: String
    ) async throws -> RemoteLocaleNote {
        if let updateStoreMetadataFieldError {
            throw updateStoreMetadataFieldError
        }
        lastUpdatedStoreMetadataField = (field, value)
        var metadata =
            lastUpdatedStoreMetadata
            ?? StoreMetadataFields(
                description: "Remote description",
                keywords: "remote,keywords",
                promotionalText: "Remote promo",
                supportURL: "https://example.com/support",
                marketingURL: "https://example.com"
            )
        metadata.setValue(value, for: field)
        lastUpdatedStoreMetadata = metadata
        let remote = fetchedLocalizations.first { $0.localizationId == localizationId }
        return RemoteLocaleNote(
            localizationId: localizationId,
            locale: remote?.locale ?? "en-US",
            text: remote?.text ?? "",
            storeMetadata: metadata
        )
    }
    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote {
        createLocalizationCallCount += 1
        if let createLocalizationError {
            throw createLocalizationError
        }
        return RemoteLocaleNote(localizationId: "loc-\(UUID().uuidString)", locale: locale, text: text)
    }
    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion {
        ReleaseVersion(
            id: "new-v", appId: appId, versionString: versionString,
            platform: "iOS", appStoreState: .prepareForSubmission)
    }
    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build] { builds }
    func fetchAllBuilds(appId: String) async throws -> [Build] {
        if let delay = fetchAllBuildsDelayNanosecondsByApp[appId], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return allBuildsByApp[appId] ?? builds
    }
    func fetchAttachedBuild(versionId: String) async throws -> Build? {
        fetchAttachedBuildCallCount += 1
        return attachedBuild
    }
    func setBuild(_ buildId: String?, forVersion versionId: String) async throws {
        lastAttachedBuildId = buildId
        attachedBuild = builds.first { $0.id == buildId }
    }

    var lastReleaseType: String?
    var submitForReviewCalled = false
    var lastSubmitPlatform: String?
    var submitForReviewState = "WAITING_FOR_REVIEW"
    var submitForReviewError: Error?

    func updateVersion(versionId: String, releaseType: String?) async throws {
        lastReleaseType = releaseType
    }
    func replaceScreenshots(
        localizationId: String, displayType: String, files: [URL], onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) async throws -> Int {
        if let replaceScreenshotsError {
            throw replaceScreenshotsError
        }
        replacedScreenshots.append(
            (
                localizationId: localizationId,
                displayType: displayType,
                fileNames: files.map(\.lastPathComponent)
            ))
        for (index, file) in files.enumerated() {
            onProgress?(index, files.count, file.lastPathComponent)
        }
        return files.count
    }
    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet] {
        if let fetchScreenshotSetsError {
            throw fetchScreenshotSetsError
        }
        if let delay = fetchScreenshotSetDelayNanoseconds[localizationId] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return remoteScreenshotSets[localizationId] ?? []
    }
    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String {
        submitForReviewCalled = true
        lastSubmitPlatform = platform
        if let submitForReviewError {
            throw submitForReviewError
        }
        return submitForReviewState
    }
}

final class InMemoryAIKeychainStore: AIKeychainStoring, @unchecked Sendable {
    private var store: [String: String] = [:]
    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        store["\(role.rawValue):\(provider.rawValue)"] = apiKey
    }
    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        store["\(role.rawValue):\(provider.rawValue)"]
    }
    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        store["\(role.rawValue):\(provider.rawValue)"]
    }
    func delete(for provider: AIProvider, role: AIProfileRole) throws {
        store.removeValue(forKey: "\(role.rawValue):\(provider.rawValue)")
    }
}

final class InMemoryAppleAdsCredentialStore: AppleAdsCredentialStoring, @unchecked Sendable {
    private var credentials: AppleAdsCredentials?

    func load() throws -> AppleAdsCredentials? { credentials }

    func save(_ credentials: AppleAdsCredentials) throws {
        self.credentials = try credentials.validated()
    }

    func delete() throws {
        credentials = nil
    }
}

final class MockAIService: AIService, @unchecked Sendable {
    var parseResult: [String: String] = [:]
    var storeMetadataParseResult: [String: StoreMetadataFields] = [:]
    var translateResult: String = "MOCK TRANSLATION"
    var optimizedStoreMetadata = StoreMetadataFields(
        description: "Optimized description",
        keywords: "optimized,keywords",
        promotionalText: "Optimized promo",
        supportURL: "https://keep.example/support",
        marketingURL: "https://keep.example/marketing"
    )
    var parseDelayNanoseconds: UInt64 = 0
    var storeMetadataParseDelayNanoseconds: UInt64 = 0
    var optimizeDelayNanoseconds: UInt64 = 0
    var translateError: Error?
    var optimizeError: Error?
    var lastParseText: String?
    var isConfigured: Bool { true }

    func parseReleaseNotes(
        text: String, currentVersion: String?, knownRemoteLocales: [String]
    ) async throws -> [String: String] {
        if parseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: parseDelayNanoseconds)
        }
        lastParseText = text
        return parseResult
    }
    var translateDelayNanoseconds: UInt64 = 0

    func translate(
        text: String, fromLocale: String, toLocale: String, glossary: [String: String]
    ) async throws -> String {
        if let translateError {
            throw translateError
        }
        if translateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: translateDelayNanoseconds)
        }
        return translateResult
    }

    func parseStoreMetadata(
        text: String,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?
    ) async throws -> [String: StoreMetadataFields] {
        if storeMetadataParseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: storeMetadataParseDelayNanoseconds)
        }
        lastParseText = text
        return storeMetadataParseResult
    }

    func optimizeStoreMetadata(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) async throws -> StoreMetadataFields {
        if let optimizeError {
            throw optimizeError
        }
        if optimizeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: optimizeDelayNanoseconds)
        }
        return optimizedStoreMetadata
    }
}

final class MockScreenshotVisionAIService: ScreenshotVisionAIService, @unchecked Sendable {
    var assignments: [ScreenshotLocaleAssignment] = []
    var isConfigured: Bool = true

    func classifyScreenshotLocales(
        assets: [ScreenshotAsset],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        assignments
    }
}
