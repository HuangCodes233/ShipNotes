import AppKit
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShipNotes

@Suite("Screenshot reliability", .serialized)
@MainActor
struct ScreenshotReliabilityTests {
    private let root = URL(fileURLWithPath: "/fixtures/screenshots")

    private func reservation() -> ScreenshotProcessingReservation {
        .init(
            localizationId: "loc-fixture", displayType: "APP_IPHONE_65", setId: "set-fixture",
            uploaded: [.init(id: "shot-fixture", fileName: "one.png")])
    }

    private func state(
        service: MockASCService, defaults: UserDefaults, draftStore: (any WorkspaceDraftStoring)? = nil
    ) -> AppState {
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), appStoreService: service,
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(), defaults: defaults,
            workspaceDraftStore: draftStore)
        state.credentialSummary = .init(name: "Fixture", issuerId: "issuer-fixture", keyId: "KEYFIXTURE")
        state.selectedAppId = "app-fixture"
        state.selectedVersionId = "version-fixture"
        state.versionsByApp["app-fixture"] = [
            ReleaseVersion(
                id: "version-fixture", appId: "app-fixture", versionString: "1.0", platform: "iOS",
                appStoreState: .prepareForSubmission)
        ]
        return state
    }

    @Test func pendingUploadPersistsAndResumesWithoutReplacing() async {
        let defaults = makeTestDefaults()
        let service = MockASCService()
        let initial = state(service: service, defaults: defaults)
        let record = PendingScreenshotProcessing(
            appId: "app-fixture", versionId: "version-fixture", locale: "en-US", reservation: reservation())
        initial.rememberPendingScreenshotProcessing(record)
        initial.recordSyncRun(
            localeResults: ["en-US": .processing], dryRun: false, kind: .screenshots,
            appId: record.appId, versionId: record.versionId)

        let restored = state(service: service, defaults: defaults)
        #expect(restored.currentPendingScreenshotProcessing == [record])
        #expect(restored.syncHistory.first?.result == .processing)
        #expect(restored.screenshotPreviewControlsState.allDisabledReason != nil)
        await restored.checkPendingScreenshotProcessing()

        #expect(service.resumedScreenshotProcessing == [record.reservation])
        #expect(service.replacedScreenshots.isEmpty)
        #expect(restored.pendingScreenshotProcessing.isEmpty)
        #expect(restored.syncHistory.first?.localeResults["en-US"] == .succeeded)
        #expect(state(service: service, defaults: defaults).pendingScreenshotProcessing.isEmpty)
    }

    @Test func pendingProcessingIsVersionBoundAndCannotTriggerAnotherReplace() async {
        let service = MockASCService()
        let state = state(service: service, defaults: makeTestDefaults())
        let record = PendingScreenshotProcessing(
            appId: "app-fixture", versionId: "version-fixture", locale: "en-US", reservation: reservation())
        state.rememberPendingScreenshotProcessing(record)
        await state.prepareScreenshotReplacementPreview(locales: ["en-US"])
        await state.uploadScreenshotReplacementPlan(uploadPlan())
        #expect(service.replacedScreenshots.isEmpty)
        #expect(state.pendingScreenshotReplacement == nil)

        state.selectedVersionId = "another-version"
        #expect(state.currentPendingScreenshotProcessing.isEmpty)
        await state.checkPendingScreenshotProcessing()
        #expect(service.resumedScreenshotProcessing.isEmpty)
        #expect(state.pendingScreenshotProcessing.count == 1)
    }

    @Test func pendingCheckRetainsIDsUntilAppleConfirmsCompletion() async {
        let service = MockASCService()
        let state = state(service: service, defaults: makeTestDefaults())
        let record = PendingScreenshotProcessing(
            appId: "app-fixture", versionId: "version-fixture", locale: "en-US", reservation: reservation())
        state.rememberPendingScreenshotProcessing(record)
        service.resumeScreenshotProcessingError = ScreenshotProcessingPendingError(reservation: record.reservation)
        await state.checkPendingScreenshotProcessing()
        #expect(state.pendingScreenshotProcessing[record.key] == record)
        #expect(service.replacedScreenshots.isEmpty)
        #expect(!state.isCheckingScreenshotProcessing)
    }

    @Test func uploadDeadlineRecordsProcessingInsteadOfSuccess() async {
        let service = MockASCService()
        let state = state(service: service, defaults: makeTestDefaults())
        state.screenshotScan = scan([asset("one.png", hash: "hash")])
        service.replaceScreenshotsError = ScreenshotProcessingPendingError(reservation: reservation())
        await state.uploadScreenshotReplacementPlan(uploadPlan())
        #expect(state.currentPendingScreenshotProcessing.count == 1)
        #expect(state.syncHistory.first?.localeResults["en-US"] == .processing)
        #expect(state.syncHistory.first?.result == .processing)
        #expect(state.lastError == nil)
        #expect(!state.isUploadingScreenshots)
    }

    @Test func refreshRetainsOnlyUnchangedClassificationsAndOrder() {
        let state = state(service: MockASCService(), defaults: makeTestDefaults())
        let first = asset("one.png", hash: "same")
        let second = asset("two.png", hash: "old")
        let removed = asset("removed.png", hash: "removed")
        let changed = asset("two.png", hash: "new")
        let added = asset("new.png", hash: "added")
        let key = state.screenshotOrderKey(locale: "en-US", slot: .iPhone65)
        state.screenshotAILocaleOverrides = [first.id: "en-US", second.id: "ja", removed.id: "fr-FR"]
        state.screenshotAISharedAssetIDs = [first.id, second.id, removed.id]
        state.screenshotOrderByGroup = [key: [second.id, first.id, removed.id]]

        let updated = scan([first, changed, added])
        state.preserveScreenshotAdjustments(from: scan([first, second, removed]), to: updated)
        state.screenshotScan = updated
        state.reconcileScreenshotOrder()

        #expect(state.screenshotAILocaleOverrides == [first.id: "en-US"])
        #expect(state.screenshotAISharedAssetIDs == [first.id])
        #expect(state.screenshotOrderByGroup[key]?.first == first.id)
        #expect(Set(state.screenshotOrderByGroup[key] ?? []) == [first.id, changed.id, added.id])
    }

    @Test func samePathNewContentChangesThumbnailIdentity() {
        let url = root.appendingPathComponent("one.png")
        #expect(
            ScreenshotThumbnailRequest(url: url, contentHash: "old")
                != ScreenshotThumbnailRequest(url: url, contentHash: "new"))
        #expect(
            ScreenshotThumbnailRequest(url: url, contentHash: "same")
                == ScreenshotThumbnailRequest(url: url, contentHash: "same"))
    }

    @Test func uniqueImageGetsAStableHashThatChangesWhenOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shipnotes-screenshot-revision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("one.png")
        try writeTinyPNG(color: .red, to: url)
        let first = try ScreenshotScanner().scan(url: folder).assets[0]
        let same = try ScreenshotScanner().scan(url: folder).assets[0]
        try writeTinyPNG(color: .blue, to: url)
        let changed = try ScreenshotScanner().scan(url: folder).assets[0]
        #expect(first.contentHash != nil)
        #expect(first.contentHash == same.contentHash)
        #expect(first.id == changed.id)
        #expect(first.contentHash != changed.contentHash)
    }

    @Test func samePathNewRevisionLoadsNewThumbnailPixels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shipnotes-thumbnail-revision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("one.png")
        try writeTinyPNG(color: .red, to: url)
        let first = try #require(
            await ScreenshotThumbnailCache.shared.thumbnail(for: url, maxPixel: 2, contentHash: "red"))
        try writeTinyPNG(color: .blue, to: url)
        let second = try #require(
            await ScreenshotThumbnailCache.shared.thumbnail(for: url, maxPixel: 2, contentHash: "blue"))
        let firstPixels = try #require(first.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let secondPixels = try #require(second.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let red = try #require(NSBitmapImageRep(cgImage: firstPixels).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let blue = try #require(
            NSBitmapImageRep(cgImage: secondPixels).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        #expect(red.redComponent > red.blueComponent)
        #expect(blue.blueComponent > blue.redComponent)
    }

    @Test func restoredRemoteConflictSurvivesAsynchronousScreenshotScan() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shipnotes-conflict-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeTinyPNG(color: .red, to: folder.appendingPathComponent("one.png"))
        let store = InMemoryWorkspaceDraftStore()
        let defaults = makeTestDefaults()
        let original = state(service: MockASCService(), defaults: defaults, draftStore: store)
        original.remoteNotesByLocale = [
            "en-US": .init(localizationId: "loc-fixture", locale: "en-US", text: "Old remote")
        ]
        original.localeNotes = [
            original.makeNote(
                locale: "en-US", localText: "Old remote", remoteNote: original.remoteNotesByLocale["en-US"], path: nil)
        ]
        original.restoreCurrentWorkspaceDraft()
        original.updateLocalText(for: "en-US", text: "Unsynced edited draft")
        original.screenshotFolder = folder
        original.screenshotScan = try ScreenshotScanner().scan(url: folder)
        original.persistWorkspaceDraftsNow()

        let reopened = state(service: MockASCService(), defaults: defaults, draftStore: store)
        reopened.remoteNotesByLocale = [
            "en-US": .init(localizationId: "loc-fixture", locale: "en-US", text: "New remote")
        ]
        reopened.localeNotes = [
            reopened.makeNote(
                locale: "en-US", localText: "New remote", remoteNote: reopened.remoteNotesByLocale["en-US"], path: nil)
        ]
        reopened.restoreCurrentWorkspaceDraft()
        let conflict = try #require(reopened.lastError)
        #expect(await waitUntil { !reopened.isScanningScreenshots && reopened.screenshotScan != nil })
        #expect(reopened.localeNotes[0].localText == "Unsynced edited draft")
        #expect(reopened.lastError?.id == conflict.id)
    }

    @Test func processingDeadlineReturnsPendingAndCapsSleep() async throws {
        let clock = ScreenshotTestClock()
        ScreenshotReliabilityURLProtocol.store.reset { _ in (200, Self.deliveryJSON(state: "PROCESSING")) }
        let client = makeClient()
        let polling = ScreenshotProcessingPolling(
            timeout: .seconds(3), firstDelay: .seconds(2), maxDelay: .seconds(8),
            now: { clock.now }, sleep: { clock.advance($0) })
        do {
            _ = try await client.resumeScreenshotProcessing(reservation(), polling: polling)
            Issue.record("Unconfirmed asset must remain pending")
        } catch let error as ScreenshotProcessingPendingError {
            #expect(error.reservation == reservation())
        }
        #expect(clock.sleeps == [.seconds(2), .seconds(1)])
        #expect(ScreenshotReliabilityURLProtocol.store.requests.count == 2)
        #expect(ScreenshotReliabilityURLProtocol.store.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func resumedProcessingOnlyReadsAssetsAndFinishesOrder() async throws {
        ScreenshotReliabilityURLProtocol.store.reset { request in
            if request.httpMethod == "GET" {
                return (
                    200,
                    #"{"data":[{"type":"appScreenshots","id":"shot-fixture","attributes":{"assetDeliveryState":{"state":"COMPLETE"}}},{"type":"appScreenshots","id":"shot-second","attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}]}"#
                )
            }
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/v1/appScreenshotSets/set-fixture/relationships/appScreenshots")
            return (204, "")
        }
        var record = reservation()
        record.uploaded.append(.init(id: "shot-second", fileName: "two.png"))
        let count = try await makeClient().resumeScreenshotProcessing(record)
        #expect(count == 2)
        #expect(ScreenshotReliabilityURLProtocol.store.requests.map(\.httpMethod) == ["GET", "PATCH"])
    }

    @Test func resumedRejectedAssetIsReportedWithoutDeletingIt() async throws {
        ScreenshotReliabilityURLProtocol.store.reset { _ in (200, Self.deliveryJSON(state: "FAILED")) }
        do {
            _ = try await makeClient().resumeScreenshotProcessing(reservation())
            Issue.record("Apple's rejection must not be reported as completion")
        } catch let error as AppStoreConnectClientError {
            guard case .screenshotProcessingFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(ScreenshotReliabilityURLProtocol.store.requests.map(\.httpMethod) == ["GET"])
    }

    @Test func cancelledMapStopsSchedulingAndCancelsInflightWork() async {
        let probe = ScreenshotMapProbe()
        let task = Task {
            await mapConcurrently(Array(0..<20), maxConcurrent: 2) { item in
                probe.didStart()
                do { try await Task.sleep(for: .seconds(30)) } catch { probe.didCancel() }
                return item
            }
        }
        #expect(await waitUntil { probe.started == 2 })
        task.cancel()
        let values = await task.value
        #expect(probe.started == 2)
        #expect(probe.cancelled == 2)
        #expect(values.count <= 2)
    }

    @Test func oldHistoryPayloadStillDecodesWithoutSnapshotsOrProcessing() throws {
        let payload =
            #"{"id":"00000000-0000-0000-0000-000000000001","appId":"app","versionId":"v","startedAt":0,"dryRun":false,"localeResults":{"en-US":{"succeeded":{}}}}"#
        let run = try JSONDecoder().decode(SyncRun.self, from: Data(payload.utf8))
        #expect(run.result == .success)
        #expect(run.appName == nil)
        #expect(run.versionString == nil)
    }

    private func asset(_ name: String, hash: String) -> ScreenshotAsset {
        .init(
            url: root.appendingPathComponent(name), relativePath: name, size: .init(width: 1242, height: 2688),
            locale: "en-US", deviceSlot: .iPhone65, status: .ready, contentHash: hash)
    }

    private func scan(_ assets: [ScreenshotAsset]) -> ScreenshotScan {
        .init(inputRoot: root, root: root, sourceKind: .directFolder, assets: assets, skippedCount: 0)
    }

    private func uploadPlan() -> ScreenshotReplacementPlan {
        .init(
            locales: [
                .init(
                    locale: "en-US", localizationId: "loc-fixture",
                    slots: [
                        .init(slot: .iPhone65, remoteScreenshots: [], localAssets: [asset("one.png", hash: "hash")])
                    ])
            ], appId: "app-fixture", versionId: "version-fixture")
    }

    private enum FixtureColor { case red, blue }

    private func writeTinyPNG(color: FixtureColor, to url: URL) throws {
        // Paint into a private RGBA buffer, independent of AppKit's global
        // appearance and graphics state, which other test suites can change.
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let red: CGFloat = color == .red ? 1 : 0
        let blue: CGFloat = color == .blue ? 1 : 0
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func makeClient() -> AppStoreConnectClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScreenshotReliabilityURLProtocol.self]
        let credentials = AppStoreConnectCredentials(
            name: "Fixture", issuerId: "issuer-fixture", keyId: "KEYFIXTURE",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
        return .init(credentials: credentials, session: URLSession(configuration: configuration))
    }

    nonisolated private static func deliveryJSON(state: String) -> String {
        #"{"data":[{"type":"appScreenshots","id":"shot-fixture","attributes":{"assetDeliveryState":{"state":"\#(state)"}}}]}"#
    }
}

private final class ScreenshotTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: Duration = .zero
    private var delays: [Duration] = []
    var now: Duration { lock.withLock { elapsed } }
    var sleeps: [Duration] { lock.withLock { delays } }
    func advance(_ duration: Duration) {
        lock.withLock {
            elapsed += duration; delays.append(duration)
        }
    }
}

private final class ScreenshotMapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var cancellations = 0
    var started: Int { lock.withLock { starts } }
    var cancelled: Int { lock.withLock { cancellations } }
    func didStart() { lock.withLock { starts += 1 } }
    func didCancel() { lock.withLock { cancellations += 1 } }
}

private final class ScreenshotReliabilityURLProtocol: URLProtocol, @unchecked Sendable {
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: @Sendable (URLRequest) -> (Int, String) = { _ in (500, "") }
        private var received: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { received } }
        func reset(_ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
            lock.withLock {
                self.handler = handler; received = []
            }
        }
        func respond(to request: URLRequest) -> (Int, String) {
            let callback = lock.withLock {
                received.append(request); return handler
            }
            return callback(request)
        }
    }
    static let store = Store()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.store.respond(to: request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
