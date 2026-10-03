import Foundation
import Testing
@testable import ShipNotes

@Suite("AI Integration")
@MainActor
struct AIIntegrationTests {
    @Test func appStateExposesUnconfiguredServiceByDefault() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        #expect(state.isAIConfigured == false)
        #expect(state.selectedAIProvider == .none)
    }

    @Test func savingKeyMakesServiceConfigured() {
        let keychain = InMemoryAIKeychainStore()
        let state = AppState(aiKeychainStore: keychain, defaults: makeTestDefaults())
        state.saveAIKey("sk-ant-test-key-xxx", for: .anthropic)
        #expect(state.isAIConfigured == true)
        #expect(state.selectedAIProvider == .anthropic)
        #expect((try? keychain.load(for: .anthropic)) == "sk-ant-test-key-xxx")
    }

    @Test func removingKeyMakesServiceUnconfigured() {
        let keychain = InMemoryAIKeychainStore()
        let state = AppState(aiKeychainStore: keychain, defaults: makeTestDefaults())
        state.saveAIKey("sk-ant-test-key-xxx", for: .anthropic)
        state.removeAIKey(for: .anthropic)
        #expect(state.isAIConfigured == false)
        #expect(state.selectedAIProvider == .none)
    }

    @Test func savingVisionKeyDoesNotConfigureTextAI() {
        let keychain = InMemoryAIKeychainStore()
        let state = AppState(aiKeychainStore: keychain, defaults: makeTestDefaults())
        state.saveVisionAIKey("sk-vision-test-key", for: .openai)
        #expect(state.isVisionAIConfigured == true)
        #expect(state.selectedVisionAIProvider == .openai)
        #expect(state.isAIConfigured == false)
        #expect(state.selectedAIProvider == .none)
        #expect((try? keychain.load(for: .openai, role: .vision)) == "sk-vision-test-key")
        #expect((try? keychain.load(for: .openai, role: .text)) == nil)
    }

    @Test func endpointResolverAcceptsRootVersionedAndFullProviderURLs() {
        let openAIRoot = URL(string: "https://api.example.com")!
        let openAIVersioned = URL(string: "https://api.example.com/v1")!
        let openAIFull = URL(string: "https://api.example.com/v1/chat/completions")!
        #expect(AIEndpointResolver.openAIChatCompletions(from: openAIRoot).path == "/v1/chat/completions")
        #expect(AIEndpointResolver.openAIChatCompletions(from: openAIVersioned).path == "/v1/chat/completions")
        #expect(AIEndpointResolver.openAIChatCompletions(from: openAIFull).path == "/v1/chat/completions")

        let anthropicRoot = URL(string: "https://anthropic.example.com")!
        let anthropicVersioned = URL(string: "https://anthropic.example.com/v1")!
        let anthropicFull = URL(string: "https://anthropic.example.com/v1/messages")!
        #expect(AIEndpointResolver.anthropicMessages(from: anthropicRoot).path == "/v1/messages")
        #expect(AIEndpointResolver.anthropicMessages(from: anthropicVersioned).path == "/v1/messages")
        #expect(AIEndpointResolver.anthropicMessages(from: anthropicFull).path == "/v1/messages")
    }

    @Test func providerBadRequestPreservesItsActualReason() {
        let rejected = Data(
            #"{"error":{"message":"The request was rejected because it was considered high risk"}}"#.utf8)
        do {
            try AIRequestPolicy.validate(statusCode: 400, data: rejected)
            Issue.record("Expected request-rejected error")
        } catch let error as AIServiceError {
            guard case .requestRejected(let message) = error else {
                Issue.record("Expected requestRejected, got \(error)")
                return
            }
            #expect(message.contains("high risk"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try AIRequestPolicy.validate(statusCode: 400, data: Data(#"{"error":{"message":"unknown model"}}"#.utf8))
            Issue.record("Expected invalid-response error")
        } catch let error as AIServiceError {
            guard case .invalidResponse(let message) = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
            #expect(message.contains("unknown model"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try AIRequestPolicy.validate(
                statusCode: 400,
                data: Data(#"{"error":{"message":"maximum context length exceeded"}}"#.utf8)
            )
            Issue.record("Expected token-limit error")
        } catch let error as AIServiceError {
            guard case .tokenLimitExceeded = error else {
                Issue.record("Expected tokenLimitExceeded, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func askAIToParseAppliesLocalesFromMockService() async {
        let mock = MockAIService()
        mock.parseResult = ["en-US": "• Mocked English release notes", "ja": "• モックの日本語"]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()  // populates apps + selects a version
        let folder = FileManager.default.temporaryDirectory.appending(path: "AI-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "anything.md")
        try? "doesn't matter, mock ignores it".write(to: url, atomically: true, encoding: .utf8)

        state.askAIToParse(url: url)
        for _ in 0..<50 {
            if state.localeNotes.contains(where: { $0.localText.contains("Mocked English") }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Mocked English") == true)
        #expect(state.localeNotes.first { $0.locale == "ja" }?.localText.contains("モックの日本語") == true)
    }

    @Test func translateLocaleAppliesResultFromMockService() async {
        let mock = MockAIService()
        mock.translateResult = "翻译后的中文文案。"
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        guard
            let firstWithText = state.localeNotes.first(where: {
                !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            let target = state.localeNotes.first(where: { $0.locale != firstWithText.locale })?.locale
        else {
            Issue.record("Mock setup needs at least two locale notes with text"); return
        }
        state.translateLocale(target, fromLocale: firstWithText.locale)
        for _ in 0..<50 {
            if state.localeNotes.first(where: { $0.locale == target })?.localText.contains("翻译") == true { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(state.localeNotes.first { $0.locale == target }?.localText.contains("翻译") == true)
    }

    @Test func translateFailsCleanlyWhenAIUnconfigured() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        guard let first = state.localeNotes.first,
            let target = state.localeNotes.dropFirst().first?.locale
        else {
            Issue.record("Need at least 2 locale notes in preview state"); return
        }
        state.translateLocale(target, fromLocale: first.locale)
        #expect(state.lastError != nil)
    }

    @Test func screenshotAIMatchingCanAddAdditionalScreenshotsToCoveredLocale() async {
        let vision = MockScreenshotVisionAIService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), visionAIService: vision, defaults: makeTestDefaults())
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-en",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let covered = ScreenshotAsset(
            url: root.appending(path: "en-US/iphone.png"),
            relativePath: "en-US/iphone.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "en-US",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        let unassigned = ScreenshotAsset(
            url: root.appending(path: "final_01_home.png"),
            relativePath: "final_01_home.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: nil,
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [covered, unassigned],
            skippedCount: 0
        )
        vision.assignments = [
            ScreenshotLocaleAssignment(assetID: unassigned.id, locale: "en-US", confidence: 0.9, reason: "English UI")
        ]

        state.askAIToClassifyScreenshots()
        for _ in 0..<50 where state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(state.screenshotCoverageGroups.first { $0.locale == "en-US" }?.count(for: .iPhone69) == 2)
        #expect(state.screenshotCoverageGroups.first { $0.isUnassigned } == nil)
        #expect(
            state.screenshotUploadSummary
                == expectedLocalized(
                    "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", 1))
    }

    @Test func screenshotAIMatchingStillFillsMissingRequiredSlots() async {
        let vision = MockScreenshotVisionAIService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), visionAIService: vision, defaults: makeTestDefaults())
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-en",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let unassigned = ScreenshotAsset(
            url: root.appending(path: "final_01_home.png"),
            relativePath: "final_01_home.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: nil,
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [unassigned],
            skippedCount: 0
        )
        vision.assignments = [
            ScreenshotLocaleAssignment(assetID: unassigned.id, locale: "en-US", confidence: 0.9, reason: "English UI")
        ]

        state.askAIToClassifyScreenshots()
        for _ in 0..<50 where state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(state.screenshotCoverageGroups.first { $0.locale == "en-US" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.isUnassigned } == nil)
        #expect(
            state.screenshotUploadSummary
                == expectedLocalized(
                    "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", 1))
    }

    @Test func screenshotAIMatchingAppliesMultipleVisibleLanguageAssignmentsWithoutLocaleFolders() async {
        let vision = MockScreenshotVisionAIService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), visionAIService: vision, defaults: makeTestDefaults())
        state.localeNotes = [
            LocaleNote(
                locale: "zh-Hans",
                remoteLocalizationId: "loc-zh",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let assets = (1...5).map { index in
            ScreenshotAsset(
                url: root.appending(path: "upload/iphone-6.5/\(index).png"),
                relativePath: "upload/iphone-6.5/\(index).png",
                size: ScreenshotPixelSize(width: 1242, height: 2688),
                locale: nil,
                deviceSlot: .iPhone65,
                status: .ready,
                contentHash: "\(index)"
            )
        }
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: assets,
            skippedCount: 0
        )
        vision.assignments = assets.map {
            ScreenshotLocaleAssignment(
                assetID: $0.id, locale: "zh-Hans", confidence: 0.95, reason: "Simplified Chinese UI text")
        }

        state.askAIToClassifyScreenshots()
        for _ in 0..<50 where state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hans" }?.count(for: .iPhone65) == 5)
        #expect(state.screenshotCoverageGroups.first { $0.isUnassigned } == nil)
        #expect(
            state.screenshotUploadSummary
                == expectedLocalized(
                    "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", 5))
    }

    @Test func screenshotAIMatchingCanReassignSameLanguageCandidateToMissingLocale() async {
        let vision = MockScreenshotVisionAIService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), visionAIService: vision, defaults: makeTestDefaults())
        state.localeNotes = ["zh-Hans", "zh-Hant"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let simplifiedCandidate = ScreenshotAsset(
            url: root.appending(path: "zh-Hans/phone.png"),
            relativePath: "zh-Hans/phone.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "zh-Hans",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [simplifiedCandidate],
            skippedCount: 0
        )
        #expect(state.canClassifyScreenshotsWithAI == true)

        vision.assignments = [
            ScreenshotLocaleAssignment(
                assetID: simplifiedCandidate.id, locale: "zh-Hant", confidence: 0.92, reason: "Traditional Chinese UI")
        ]
        state.askAIToClassifyScreenshots()
        for _ in 0..<50 where state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.count(for: .iPhone69) == 1)
        #expect(
            state.screenshotUploadSummary
                == expectedLocalized(
                    "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", 1))
    }

    @Test func aiRequestPolicyUsesLongTimeoutAndRetriesOnlyConnectionFailures() {
        #expect(AIRequestPolicy.requestTimeout == 240)
        // The provider may already have generated (and billed) the answer.
        #expect(!AIRequestPolicy.isRetryableNetworkError(URLError(.timedOut)))
        #expect(!AIRequestPolicy.isRetryableNetworkError(URLError(.networkConnectionLost)))
        #expect(AIRequestPolicy.isRetryableNetworkError(URLError(.cannotConnectToHost)))
        #expect(AIRequestPolicy.isRetryableNetworkError(URLError(.cannotFindHost)))
        #expect(AIRequestPolicy.isRetryableNetworkError(URLError(.dnsLookupFailed)))
        #expect(!AIRequestPolicy.isRetryableNetworkError(URLError(.userAuthenticationRequired)))
    }
}
