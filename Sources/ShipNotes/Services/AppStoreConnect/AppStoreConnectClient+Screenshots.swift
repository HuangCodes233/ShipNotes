import CryptoKit
import Foundation
import OSLog

/// Injectable monotonic clock/sleep for deterministic processing tests.
struct ScreenshotProcessingPolling: Sendable {
    var timeout: Duration
    var firstDelay: Duration
    var maxDelay: Duration
    var now: @Sendable () -> Duration
    var sleep: @Sendable (Duration) async throws -> Void

    static var live: Self {
        let clock = ContinuousClock()
        let start = clock.now
        return Self(
            timeout: .seconds(90), firstDelay: .seconds(2), maxDelay: .seconds(8),
            now: { start.duration(to: clock.now) },
            sleep: { try await Task.sleep(for: $0) }
        )
    }
}

// Screenshot set fetch, multipart upload, and replacement.
extension AppStoreConnectClient {
    func replaceScreenshots(
        localizationId: String, displayType: String, files: [URL],
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async throws -> Int {
        guard !files.isEmpty else { return 0 }
        try Task.checkCancellation()
        // Fail before ANY destructive change if the batch can't fit in one
        // set — a mid-upload discovery would leave a partial replacement.
        guard files.count <= Self.maxScreenshotsPerSet else {
            throw AppStoreConnectClientError.requestFailed(
                statusCode: 400,
                message: "Cannot upload \(files.count) screenshots: a set holds at most \(Self.maxScreenshotsPerSet)."
            )
        }

        // Check every local file BEFORE any destructive change, so an
        // unreadable file fails while the remote screenshots are intact. Only
        // metadata is read here; each file's bytes are loaded right before its
        // upload, keeping one screenshot (not a whole set) in memory at a time.
        try await Self.validateReadableFiles(files)

        let set = try await findOrCreateScreenshotSet(
            localizationId: localizationId,
            displayType: displayType
        )
        // Replace one locale/display-type set at a time. Never mix old and
        // new reservations near the set's capacity limit.
        let oldScreenshots = try await requestCollection(
            ASCAppScreenshotResource.self,
            path: "appScreenshotSets/\(set.id)/appScreenshots",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "fields[appScreenshots]", value: "fileName,fileSize,assetDeliveryState"),
            ]
        )

        for screenshot in oldScreenshots {
            try Task.checkCancellation()
            try await deleteResource(path: "appScreenshots/\(screenshot.id)")
        }
        if !oldScreenshots.isEmpty {
            try await waitForEmptyScreenshotSet(setId: set.id)
        }

        var uploaded: [ScreenshotProcessingReservation.UploadedFile] = []
        for (index, fileURL) in files.enumerated() {
            try Task.checkCancellation()
            let fileName = fileURL.lastPathComponent
            let data = try await Self.readFile(fileURL)

            let created = try await createScreenshotUploadResource(
                setId: set.id,
                fileName: fileName,
                fileSize: data.count
            )
            do {
                try await uploadScreenshotData(data, using: created.attributes?.uploadOperations ?? [])
                try await markScreenshotUploaded(id: created.id, data: data)
            } catch {
                // Don't leave an empty reservation occupying a slot in the set.
                await discardScreenshot(id: created.id)
                throw error
            }
            uploaded.append(.init(id: created.id, fileName: fileName))
            onProgress?(index, files.count, fileName)
        }

        // `uploaded: true` only starts Apple's processing. A file rejected at
        // this stage (alpha channel, corrupt image, wrong size) would leave a
        // broken asset behind while we report success, so check the result.
        return try await finishScreenshotProcessing(
            .init(
                localizationId: localizationId, displayType: displayType,
                setId: set.id, uploaded: uploaded
            ), polling: .live, removesRejectedUploads: true)
    }

    /// A successful DELETE may precede the collection reflecting that change.
    /// Read it back before creating any new reservations; if it stays nonempty,
    /// stop instead of recreating the capacity-sensitive interleaving.
    func waitForEmptyScreenshotSet(setId: String) async throws {
        for attempt in 0..<6 {
            try Task.checkCancellation()
            let remaining = try await fetchScreenshots(setId: setId)
            if remaining.isEmpty { return }
            if attempt < 5 {
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw AppStoreConnectClientError.screenshotDeletionNotConfirmed
    }

    func resumeScreenshotProcessing(_ reservation: ScreenshotProcessingReservation) async throws -> Int {
        try await resumeScreenshotProcessing(reservation, polling: .live)
    }

    /// Timeout and an interrupted status read preserve the uploaded IDs. The
    /// caller can resume these checks without performing a destructive replace.
    func resumeScreenshotProcessing(
        _ original: ScreenshotProcessingReservation,
        polling: ScreenshotProcessingPolling
    ) async throws -> Int {
        try await finishScreenshotProcessing(original, polling: polling, removesRejectedUploads: false)
    }

    private func finishScreenshotProcessing(
        _ original: ScreenshotProcessingReservation,
        polling: ScreenshotProcessingPolling,
        removesRejectedUploads: Bool
    ) async throws -> Int {
        var reservation = original
        let outcome:
            (
                pending: [ScreenshotProcessingReservation.UploadedFile],
                failures: [(id: String, fileName: String, reason: String)]
            )
        do {
            outcome = try await waitForScreenshotProcessing(
                reservation.uploaded, setId: reservation.setId, polling: polling)
        } catch {
            throw ScreenshotProcessingPendingError(reservation: reservation)
        }
        for failure in outcome.failures {
            if removesRejectedUploads { await discardScreenshot(id: failure.id) }
            reservation.failureDetails.append("\(failure.fileName): \(failure.reason)")
        }
        let failedIDs = Set(outcome.failures.map(\.id))
        reservation.uploaded.removeAll { failedIDs.contains($0.id) }
        guard outcome.pending.isEmpty else {
            throw ScreenshotProcessingPendingError(reservation: reservation)
        }
        guard reservation.failureDetails.isEmpty else {
            throw AppStoreConnectClientError.screenshotProcessingFailed(
                reservation.failureDetails.joined(separator: "\n"))
        }

        let uploadedIDs = reservation.uploaded.map(\.id)
        if uploadedIDs.count > 1 {
            do {
                try await patchRelationship(
                    path: "appScreenshotSets/\(reservation.setId)/relationships/appScreenshots",
                    body: ASCAppScreenshotOrderRequest(ids: uploadedIDs)
                )
            } catch {
                throw ScreenshotProcessingPendingError(reservation: reservation)
            }
        }
        return uploadedIDs.count
    }

    /// One set request per poll covers all uploaded screenshots. Every sleep
    /// is capped by the remaining deadline; pending assets never mean success.
    func waitForScreenshotProcessing(
        _ screenshots: [ScreenshotProcessingReservation.UploadedFile],
        setId: String,
        polling: ScreenshotProcessingPolling = .live
    ) async throws -> (
        pending: [ScreenshotProcessingReservation.UploadedFile],
        failures: [(id: String, fileName: String, reason: String)]
    ) {
        var pending = screenshots
        var failures: [(id: String, fileName: String, reason: String)] = []
        let deadline = polling.now() + max(.zero, polling.timeout)
        var delay = max(.milliseconds(1), polling.firstDelay)

        while !pending.isEmpty {
            try Task.checkCancellation()
            let states = try await fetchScreenshotDeliveryStates(setId: setId)
            var stillProcessing: [ScreenshotProcessingReservation.UploadedFile] = []
            for screenshot in pending {
                let delivery = states[screenshot.id]
                switch delivery?.state {
                case "COMPLETE":
                    continue
                case "FAILED":
                    let reason = (delivery?.errors ?? [])
                        .compactMap { $0.description ?? $0.code }
                        .joined(separator: "; ")
                    failures.append((screenshot.id, screenshot.fileName, reason.isEmpty ? "processing failed" : reason))
                default:
                    stillProcessing.append(screenshot)
                }
            }
            pending = stillProcessing
            guard !pending.isEmpty else { break }
            let remaining = deadline - polling.now()
            guard remaining > .zero else {
                Logger.network.info("Screenshot processing deadline reached; preserving pending uploads.")
                break
            }
            try await polling.sleep(min(delay, remaining))
            guard polling.now() < deadline else { break }
            delay = min(delay * 2, max(.milliseconds(1), polling.maxDelay))
        }
        return (pending, failures)
    }

    func fetchScreenshotDeliveryStates(setId: String) async throws -> [String: ASCAssetDeliveryState] {
        let screenshots = try await requestCollection(
            ASCAppScreenshotResource.self,
            path: "appScreenshotSets/\(setId)/appScreenshots",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "fields[appScreenshots]", value: "assetDeliveryState"),
            ]
        )
        var states: [String: ASCAssetDeliveryState] = [:]
        for screenshot in screenshots {
            if let state = screenshot.attributes?.assetDeliveryState {
                states[screenshot.id] = state
            }
        }
        return states
    }

    /// Best-effort removal of a screenshot this upload created. Runs in its own
    /// task so it still goes out when the upload itself was cancelled.
    func discardScreenshot(id: String) async {
        await Task {
            try? await deleteResource(path: "appScreenshots/\(id)")
        }.value
    }

    static func validateReadableFiles(_ files: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            for fileURL in files {
                let values = try fileURL.resourceValues(forKeys: [.isReadableKey, .fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, values.isReadable == true, (values.fileSize ?? 0) > 0 else {
                    throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: fileURL.path])
                }
            }
        }.value
    }

    /// Screenshot files are several MB; read them off the caller's actor.
    static func readFile(_ fileURL: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: fileURL)
        }.value
    }

    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet] {
        // One request per localization: the sets and their screenshots come
        // back together instead of one extra request per display type.
        let response: ASCScreenshotSetsWithScreenshotsResponse
        do {
            let url = try makeURL(
                path: "appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
                queryItems: [
                    URLQueryItem(name: "limit", value: "50"),
                    URLQueryItem(name: "include", value: "appScreenshots"),
                    URLQueryItem(name: "limit[appScreenshots]", value: "50"),
                    URLQueryItem(name: "fields[appScreenshotSets]", value: "screenshotDisplayType,appScreenshots"),
                    URLQueryItem(name: "fields[appScreenshots]", value: "fileName,fileSize,imageAsset"),
                ]
            )
            response = try await send(
                try await makeRequest(url: url), as: ASCScreenshotSetsWithScreenshotsResponse.self)
        } catch AppStoreConnectClientError.requestFailed(statusCode: 400, _) {
            // An API revision that rejects the include parameters still
            // supports the per-set requests.
            return try await fetchScreenshotSetsOneByOne(localizationId: localizationId)
        }

        let screenshotsByID = Dictionary(
            (response.included ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var remoteSets: [RemoteScreenshotSet] = []
        for set in response.data {
            let screenshots: [ASCAppScreenshotResource]
            if let ids = set.relationships?.appScreenshots?.data {
                screenshots = ids.compactMap { screenshotsByID[$0.id] }
            } else {
                screenshots = try await fetchScreenshots(setId: set.id)
            }
            remoteSets.append(Self.remoteScreenshotSet(set, localizationId: localizationId, screenshots: screenshots))
        }
        return remoteSets
    }

    private func fetchScreenshotSetsOneByOne(localizationId: String) async throws -> [RemoteScreenshotSet] {
        let sets = try await requestCollection(
            ASCAppScreenshotSetResource.self,
            path: "appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "fields[appScreenshotSets]", value: "screenshotDisplayType"),
            ]
        )
        var remoteSets: [RemoteScreenshotSet] = []
        for set in sets {
            let screenshots = try await fetchScreenshots(setId: set.id)
            remoteSets.append(Self.remoteScreenshotSet(set, localizationId: localizationId, screenshots: screenshots))
        }
        return remoteSets
    }

    private func fetchScreenshots(setId: String) async throws -> [ASCAppScreenshotResource] {
        try await requestCollection(
            ASCAppScreenshotResource.self,
            path: "appScreenshotSets/\(setId)/appScreenshots",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "fields[appScreenshots]", value: "fileName,fileSize,imageAsset"),
            ]
        )
    }

    static func remoteScreenshotSet(
        _ set: ASCAppScreenshotSetResource,
        localizationId: String,
        screenshots: [ASCAppScreenshotResource]
    ) -> RemoteScreenshotSet {
        let displayType = set.attributes?.screenshotDisplayType ?? ""
        return RemoteScreenshotSet(
            id: set.id,
            localizationId: localizationId,
            displayType: displayType,
            slot: ScreenshotDeviceSlot.matching(displayType: displayType),
            screenshots: screenshots.map(Self.remoteScreenshot)
        )
    }

    static func remoteScreenshot(from resource: ASCAppScreenshotResource) -> RemoteScreenshot {
        RemoteScreenshot(
            id: resource.id,
            fileName: resource.attributes?.fileName ?? "Screenshot \(resource.id)",
            fileSize: resource.attributes?.fileSize,
            imageURL: displayURL(from: resource.attributes?.imageAsset),
            width: resource.attributes?.imageAsset?.width,
            height: resource.attributes?.imageAsset?.height
        )
    }

    /// Width requested for preview thumbnails. The tiles are 104 pt wide, so
    /// this stays sharp at 2x while downloading a small JPEG instead of the
    /// full-resolution PNG (a 1320×2868 original is several megabytes).
    static let thumbnailPixelWidth = 240

    static func displayURL(from imageAsset: ASCImageAsset?) -> URL? {
        guard var template = imageAsset?.templateUrl else { return nil }
        let originalWidth = max(imageAsset?.width ?? 300, 1)
        let originalHeight = max(imageAsset?.height ?? 650, 1)
        let width = min(thumbnailPixelWidth, originalWidth)
        let height = max(1, Int((Double(width) * Double(originalHeight) / Double(originalWidth)).rounded()))
        template = template.replacingOccurrences(of: "{w}", with: "\(width)")
        template = template.replacingOccurrences(of: "{h}", with: "\(height)")
        template = template.replacingOccurrences(of: "{f}", with: "jpg")
        return URL(string: template)
    }

    func findOrCreateScreenshotSet(
        localizationId: String,
        displayType: String
    ) async throws -> ASCAppScreenshotSetResource {
        let sets = try await requestCollection(
            ASCAppScreenshotSetResource.self,
            path: "appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "fields[appScreenshotSets]", value: "screenshotDisplayType"),
            ]
        )
        if let existing = sets.first(where: { $0.attributes?.screenshotDisplayType == displayType }) {
            return existing
        }

        let body = ASCAppScreenshotSetCreateRequest(
            localizationId: localizationId,
            displayType: displayType
        )
        return try await requestResource(
            ASCAppScreenshotSetResource.self,
            path: "appScreenshotSets",
            method: "POST",
            body: body
        )
    }

    func createScreenshotUploadResource(
        setId: String,
        fileName: String,
        fileSize: Int
    ) async throws -> ASCAppScreenshotResource {
        let body = ASCAppScreenshotCreateRequest(
            setId: setId,
            fileName: fileName,
            fileSize: fileSize
        )
        return try await requestResource(
            ASCAppScreenshotResource.self,
            path: "appScreenshots",
            method: "POST",
            body: body
        )
    }

    func uploadScreenshotData(_ data: Data, using operations: [ASCUploadOperation]) async throws {
        guard !operations.isEmpty else {
            throw AppStoreConnectClientError.invalidUploadOperation("missing uploadOperations")
        }

        for operation in operations {
            guard let url = operation.url else {
                throw AppStoreConnectClientError.invalidUploadOperation("missing URL")
            }
            guard operation.offset >= 0, operation.length >= 0 else {
                throw AppStoreConnectClientError.invalidUploadOperation("negative offset or length")
            }
            let end = operation.offset + operation.length
            guard end <= data.count else {
                throw AppStoreConnectClientError.invalidUploadOperation("byte range exceeds file size")
            }

            var request = URLRequest(url: url)
            request.httpMethod = operation.method ?? "PUT"
            request.timeoutInterval = Self.uploadTimeout
            request.httpBody = data.subdata(in: operation.offset..<end)
            for header in operation.requestHeaders ?? [] {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            }

            let (responseData, urlResponse) = try await performDataRequest(request)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw AppStoreConnectClientError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                let message = String(data: responseData, encoding: .utf8) ?? "Screenshot binary upload failed"
                throw AppStoreConnectClientError.requestFailed(statusCode: http.statusCode, message: message)
            }
        }
    }

    func markScreenshotUploaded(id: String, data: Data) async throws {
        let body = ASCAppScreenshotUpdateRequest(
            id: id,
            uploaded: true,
            sourceFileChecksum: Self.md5Hex(data)
        )
        try await requestWithoutDecoding(
            path: "appScreenshots/\(id)",
            method: "PATCH",
            body: body
        )
    }

    static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
