import Foundation

struct MockAppStoreConnect {
    static func sampleAccount() -> Account {
        Account(
            id: UUID().uuidString,
            name: "Mock Account",
            issuerId: "00000000-0000-0000-0000-000000000000",
            keyId: "ABCD1234EF",
            privateKeyReference: "keychain:mock",
            createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 30),
            lastUsedAt: Date()
        )
    }

    static func sampleApps() -> [AppRecord] {
        [
            AppRecord(id: "app-1", name: "Example Gallery",  bundleId: "com.example.examplegallery", platform: "iOS",   iconSystemName: "tray.full"),
            AppRecord(id: "app-2", name: "Example Timer",        bundleId: "com.example.exampletimer",      platform: "iOS",   iconSystemName: "timer"),
            AppRecord(id: "app-3", name: "ShipNotes",         bundleId: "org.shipnotes.app",    platform: "macOS", iconSystemName: "shippingbox"),
        ]
    }

    static func sampleVersions(for appId: String) -> [ReleaseVersion] {
        let calendar = Calendar.current
        let now = Date()
        switch appId {
        case "app-1":
            return [
                ReleaseVersion(id: "v-1-1", appId: appId, versionString: "1.4.0", platform: "iOS", appStoreState: .prepareForSubmission, createdDate: calendar.date(byAdding: .day, value: -3, to: now)),
                ReleaseVersion(id: "v-1-2", appId: appId, versionString: "1.3.0", platform: "iOS", appStoreState: .readyForSale, createdDate: calendar.date(byAdding: .day, value: -30, to: now)),
            ]
        case "app-2":
            return [
                ReleaseVersion(id: "v-2-1", appId: appId, versionString: "2.0.0", platform: "iOS", appStoreState: .waitingForReview, createdDate: calendar.date(byAdding: .day, value: -5, to: now)),
                ReleaseVersion(id: "v-2-2", appId: appId, versionString: "1.9.0", platform: "iOS", appStoreState: .readyForSale, createdDate: calendar.date(byAdding: .day, value: -45, to: now)),
            ]
        case "app-3":
            return [
                ReleaseVersion(id: "v-3-1", appId: appId, versionString: "0.1.0", platform: "macOS", appStoreState: .prepareForSubmission, createdDate: calendar.date(byAdding: .day, value: -1, to: now)),
            ]
        default:
            return []
        }
    }

    /// Remote `whatsNew` text indexed by locale, for a given version.
    static func sampleRemoteNotes(versionId: String) -> [String: String] {
        switch versionId {
        case "v-1-1":
            return [
                "en-US": """
                • Improved import speed for large libraries.
                • Fixed a rare crash when handling HEIC files.
                """,
                "zh-Hans": """
                • 优化大型图库的导入速度。
                • 修复处理 HEIC 文件时偶发崩溃。
                """,
                "ja": """
                • 大規模ライブラリの読み込み速度を改善しました。
                • HEICファイル処理時のまれなクラッシュを修正しました。
                """,
            ]
        case "v-2-1":
            return [
                "en-US": "• Bug fixes and performance improvements.",
                "zh-Hans": "• 修复一些问题，提升性能。",
            ]
        default:
            return [:]
        }
    }

    static func sampleStoreMetadata(versionId: String) -> [String: StoreMetadataFields] {
        switch versionId {
        case "v-1-1":
            return [
                "en-US": StoreMetadataFields(
                    subtitle: "App Store screenshot manager",
                    description: """
                    Example Gallery helps indie developers collect, review, and organize App Store screenshots before release. Import folders, spot missing sizes, and keep each locale's screenshot set tidy.
                    """,
                    keywords: "screenshots,app store,release,metadata,developer",
                    promotionalText: "Prepare localized App Store screenshots faster, with fewer last-minute upload surprises.",
                    supportURL: "https://example.com/support",
                    marketingURL: "https://example.com/example-gallery",
                    privacyPolicyURL: "https://example.com/privacy"
                ),
                "zh-Hans": StoreMetadataFields(
                    subtitle: "App Store 截图整理与管理",
                    description: """
                    Example Gallery 帮助独立开发者在发布前整理、检查和归类 App Store 截图。导入文件夹后，你可以快速发现缺失尺寸，并让每个语言版本的截图保持有序。
                    """,
                    keywords: "截图,App Store,发布,元数据,开发者",
                    promotionalText: "更快准备本地化商店截图，减少提交前的临时返工。",
                    supportURL: "https://example.com/support",
                    marketingURL: "https://example.com/example-gallery",
                    privacyPolicyURL: "https://example.com/privacy"
                ),
                "ja": StoreMetadataFields(
                    subtitle: "App Store スクリーンショット管理",
                    description: """
                    Example Gallery は、個人開発者がリリース前に App Store スクリーンショットを整理、確認、分類するためのツールです。フォルダを読み込み、足りないサイズを見つけ、ロケールごとの素材をきれいに保てます。
                    """,
                    keywords: "スクリーンショット,App Store,リリース,メタデータ",
                    promotionalText: "ローカライズ済みのストア用スクリーンショットを、より少ない手戻りで準備できます。",
                    supportURL: "https://example.com/support",
                    marketingURL: "https://example.com/example-gallery",
                    privacyPolicyURL: "https://example.com/privacy"
                )
            ]
        case "v-2-1":
            return [
                "en-US": StoreMetadataFields(
                    subtitle: "Calm Pomodoro timer",
                    description: "Example Timer keeps short work sessions calm and easy to track.",
                    keywords: "timer,focus,pomodoro,productivity",
                    promotionalText: "A quieter timer for focused work.",
                    supportURL: "https://example.com/support",
                    marketingURL: "",
                    privacyPolicyURL: "https://example.com/privacy"
                ),
                "zh-Hans": StoreMetadataFields(
                    subtitle: "轻量专注番茄钟",
                    description: "Example Timer 让短时专注更轻量、更容易坚持。",
                    keywords: "计时器,专注,番茄钟,效率",
                    promotionalText: "一个更安静的专注计时器。",
                    supportURL: "https://example.com/support",
                    marketingURL: "",
                    privacyPolicyURL: "https://example.com/privacy"
                )
            ]
        default:
            return [:]
        }
    }

    static func sampleLocalNotes(versionId: String) -> [String: String] {
        switch versionId {
        case "v-1-1":
            return [
                "en-US": """
                • Imports are now twice as fast for large libraries.
                • Fixed a rare crash when handling HEIC files.
                • New: drag-and-drop release notes into ShipNotes.
                """,
                "zh-Hans": """
                • 大型图库导入速度提升 2 倍。
                • 修复处理 HEIC 文件时偶发崩溃。
                • 新增：将发布说明拖入 ShipNotes。
                """,
                "ja": """
                • 大規模ライブラリの読み込み速度を2倍に改善しました。
                • HEICファイル処理時のまれなクラッシュを修正しました。
                • 新機能：リリースノートをShipNotesにドラッグ＆ドロップできます。
                """,
                "ko": """
                • 대용량 라이브러리의 가져오기 속도가 2배 빨라졌습니다.
                • HEIC 파일 처리 시 발생하던 드문 충돌을 수정했습니다.
                """,
            ]
        case "v-2-1":
            return [
                "en-US": "• Bug fixes and performance improvements.",
                "zh-Hans": "• 修复一些问题，提升性能。",
            ]
        default:
            return [:]
        }
    }
}

/// In-memory App Store Connect stand-in used before the user saves an API key.
/// Sync / create / submit go through `AppStoreConnectServicing` just like live,
/// so mock mode does not keep a second copy of that workflow.
final class SampleAppStoreConnectService: AppStoreConnectServicing, @unchecked Sendable {
    private var apps: [AppRecord]
    private var versionsByApp: [String: [ReleaseVersion]]
    private var localizationsByVersion: [String: [RemoteLocaleNote]]
    private var attachedBuildByVersion: [String: Build] = [:]
    private var buildsByApp: [String: [Build]] = [:]

    init() {
        apps = MockAppStoreConnect.sampleApps()
        versionsByApp = [:]
        localizationsByVersion = [:]
        for app in apps {
            let versions = MockAppStoreConnect.sampleVersions(for: app.id)
            versionsByApp[app.id] = versions
            for version in versions {
                localizationsByVersion[version.id] = Self.seededLocalizations(versionId: version.id)
            }
        }
    }

    private static func seededLocalizations(versionId: String) -> [RemoteLocaleNote] {
        // Localization IDs are `mock-{versionId}-{locale}` so the UI's
        // `loadMockNotesForCurrentVersion` can PATCH the same records.
        let notes = MockAppStoreConnect.sampleRemoteNotes(versionId: versionId)
        let metadata = MockAppStoreConnect.sampleStoreMetadata(versionId: versionId)
        return notes.keys.sorted().map { locale in
                RemoteLocaleNote(
                    localizationId: "mock-\(versionId)-\(locale)",
                    locale: locale,
                    text: notes[locale] ?? "",
                    storeMetadata: metadata[locale] ?? .empty
                )
        }
    }

    func validateCredentials() async throws {}

    func fetchApps() async throws -> [AppRecord] { apps }

    func fetchVersions(appId: String) async throws -> [ReleaseVersion] {
        versionsByApp[appId] ?? []
    }

    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote] {
        localizationsByVersion[versionId] ?? []
    }

    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote {
        try mutateLocalization(id: localizationId) { note in
            note.text = text
        }
    }

    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote {
        try mutateLocalization(id: localizationId) { note in
            note.storeMetadata = metadata
        }
    }

    func updateStoreMetadataField(localizationId: String, field: StoreCopyField, value: String) async throws -> RemoteLocaleNote {
        try mutateLocalization(id: localizationId) { note in
            note.storeMetadata.setValue(value, for: field)
        }
    }

    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote {
        let note = RemoteLocaleNote(
            localizationId: "mock-\(UUID().uuidString)",
            locale: locale,
            text: text
        )
        localizationsByVersion[versionId, default: []].append(note)
        return note
    }

    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion {
        let displayPlatform: String
        switch platform {
        case "MAC_OS": displayPlatform = "macOS"
        case "TV_OS": displayPlatform = "tvOS"
        case "VISION_OS": displayPlatform = "visionOS"
        default: displayPlatform = "iOS"
        }
        let version = ReleaseVersion(
            id: "mock-\(UUID().uuidString)",
            appId: appId,
            versionString: versionString,
            platform: displayPlatform,
            appStoreState: .prepareForSubmission
        )
        versionsByApp[appId, default: []].insert(version, at: 0)
        localizationsByVersion[version.id] = []
        return version
    }

    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build] {
        (buildsByApp[appId] ?? []).filter { $0.marketingVersion == marketingVersion }
    }

    func fetchAllBuilds(appId: String) async throws -> [Build] {
        buildsByApp[appId] ?? []
    }

    func fetchAttachedBuild(versionId: String) async throws -> Build? {
        attachedBuildByVersion[versionId]
    }

    func setBuild(_ buildId: String?, forVersion versionId: String) async throws {
        if let buildId {
            let all = buildsByApp.values.flatMap { $0 }
            attachedBuildByVersion[versionId] = all.first { $0.id == buildId }
        } else {
            attachedBuildByVersion.removeValue(forKey: versionId)
        }
    }

    func updateVersion(versionId: String, releaseType: String?) async throws {
        _ = releaseType
        _ = versionId
    }

    func replaceScreenshots(
        localizationId: String,
        displayType: String,
        files: [URL],
        onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) async throws -> Int {
        for (index, file) in files.enumerated() {
            onProgress?(index, files.count, file.lastPathComponent)
        }
        return files.count
    }

    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet] {
        []
    }

    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String {
        _ = platform
        if var versions = versionsByApp[appId],
           let index = versions.firstIndex(where: { $0.id == versionId }) {
            versions[index] = ReleaseVersion(
                id: versions[index].id,
                appId: versions[index].appId,
                versionString: versions[index].versionString,
                platform: versions[index].platform,
                appStoreState: .waitingForReview,
                createdDate: versions[index].createdDate
            )
            versionsByApp[appId] = versions
        }
        return "WAITING_FOR_REVIEW"
    }

    private func mutateLocalization(
        id: String,
        _ body: (inout RemoteLocaleNote) -> Void
    ) throws -> RemoteLocaleNote {
        for (versionId, notes) in localizationsByVersion {
            guard let index = notes.firstIndex(where: { $0.localizationId == id }) else { continue }
            var updated = notes
            body(&updated[index])
            localizationsByVersion[versionId] = updated
            return updated[index]
        }
        throw AppStoreConnectClientError.missingLocalizationId(locale: id)
    }
}
