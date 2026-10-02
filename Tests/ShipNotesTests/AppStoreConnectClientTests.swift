import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import ShipNotes

@Suite("AppStoreConnectClient", .serialized)
struct AppStoreConnectClientTests {
    @Test func aiRateLimitStopsAfterThreeRetries() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: (0..<5).map { _ in
            { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                               headerFields: ["Retry-After": "0"])!
                return (response, Data())
            }
        }))
        defer { session.invalidateAndCancel() }

        let (_, response) = try await AIRequestPolicy.data(
            for: URLRequest(url: URL(string: "https://shipnotes.invalid/retry-test")!), session: session
        )

        #expect((response as? HTTPURLResponse)?.statusCode == 429)
        #expect(StubURLProtocol.requestCount == 4)
    }

    @Test func aiRetryStopsWhenRequestSucceeds() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil,
                                               headerFields: ["Retry-After": "0"])!
                return (response, Data())
            },
            { request in Self.jsonResponse(for: request, body: #"{"ok":true}"#) }
        ]))
        defer { session.invalidateAndCancel() }

        let (data, response) = try await AIRequestPolicy.data(
            for: URLRequest(url: URL(string: "https://shipnotes.invalid/retry-test")!), session: session
        )

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Data(#"{"ok":true}"#.utf8))
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test func aiAuthenticationFailureIsNotRetried() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in Self.emptyResponse(for: request, statusCode: 401) }
        ]))
        defer { session.invalidateAndCancel() }

        let (_, response) = try await AIRequestPolicy.data(
            for: URLRequest(url: URL(string: "https://shipnotes.invalid/retry-test")!), session: session
        )

        #expect((response as? HTTPURLResponse)?.statusCode == 401)
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func allBuildsIncludeMarketingVersionFromPrereleaseRelationship() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/builds")
                let query = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
                #expect(query.queryItems?.contains(URLQueryItem(name: "filter[app]", value: "app-1")) == true)
                #expect(query.queryItems?.contains(URLQueryItem(name: "include", value: "preReleaseVersion")) == true)
                return Self.jsonResponse(
                    for: request,
                    body: """
                    {
                      "data": [
                        {
                          "id": "build-15",
                          "type": "builds",
                          "attributes": {
                            "version": "15",
                            "uploadedDate": "2026-07-27T07:32:00Z",
                            "processingState": "VALID"
                          },
                          "relationships": {
                            "preReleaseVersion": {
                              "data": { "type": "preReleaseVersions", "id": "pr-1162" }
                            }
                          }
                        }
                      ],
                      "included": [
                        {
                          "id": "pr-1162",
                          "type": "preReleaseVersions",
                          "attributes": { "version": "1.16.2", "platform": "IOS" }
                        }
                      ]
                    }
                    """
                )
            }
        ]))
        let credentials = AppStoreConnectCredentials(
            name: "Test",
            issuerId: "issuer-123",
            keyId: "KEY1234567",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
        )
        let client = AppStoreConnectClient(credentials: credentials, session: session)

        let builds = try await client.fetchAllBuilds(appId: "app-1")

        let build = try #require(builds.first)
        #expect(build.buildNumber == "15")
        #expect(build.marketingVersion == "1.16.2")
        #expect(build.platform == "IOS")
        #expect(build.processingState == .valid)
    }

    @Test func screenshotReplacementAcceptsEmptyUploadCompletionResponse() async throws {
        let imageData = Data("image".utf8)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "shipnotes-asc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let imageURL = folder.appending(path: "one.png")
        try imageData.write(to: imageURL)

        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets")
                return Self.jsonResponse(
                    for: request,
                    body: """
                    {"data":[{"id":"set-1","type":"appScreenshotSets","attributes":{"screenshotDisplayType":"APP_IPHONE_65"}}]}
                    """
                )
            },
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                return Self.jsonResponse(
                    for: request,
                    body: """
                    {
                      "data": [
                        {
                          "id": "old-shot-1",
                          "type": "appScreenshots",
                          "attributes": {
                            "fileName": "old.png",
                            "fileSize": 123,
                            "assetDeliveryState": {
                              "errors": [],
                              "warnings": null,
                              "state": "COMPLETE"
                            }
                          }
                        }
                      ]
                    }
                    """
                )
            },
            { request in
                #expect(request.httpMethod == "DELETE")
                #expect(request.url?.path == "/v1/appScreenshots/old-shot-1")
                return Self.emptyResponse(for: request, statusCode: 204)
            },
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                return Self.jsonResponse(for: request, body: #"{"data":[]}"#)
            },
            { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/v1/appScreenshots")
                return Self.jsonResponse(
                    for: request,
                    body: """
                    {
                      "data": {
                        "id": "shot-1",
                        "type": "appScreenshots",
                        "attributes": {
                          "fileName": "one.png",
                          "fileSize": 5,
                          "uploadOperations": [
                            {
                              "method": "PUT",
                              "url": "https://upload.example.test/shot-1",
                              "offset": 0,
                              "length": 5,
                              "requestHeaders": []
                            }
                          ]
                        }
                      }
                    }
                    """
                )
            },
            { request in
                #expect(request.httpMethod == "PUT")
                #expect(request.url?.host == "upload.example.test")
                return Self.emptyResponse(for: request, statusCode: 200)
            },
            { request in
                #expect(request.httpMethod == "PATCH")
                #expect(request.url?.path == "/v1/appScreenshots/shot-1")
                return Self.emptyResponse(for: request, statusCode: 204)
            },
            { request in
                // Check processing after uploading the new screenshot.
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                return Self.deliveryStateResponse(for: request, id: "shot-1", state: "COMPLETE")
            }
        ]))

        let credentials = AppStoreConnectCredentials(
            name: "Test",
            issuerId: "issuer-123",
            keyId: "KEY1234567",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
        )
        let client = AppStoreConnectClient(credentials: credentials, session: session)

        let uploaded = try await client.replaceScreenshots(
            localizationId: "loc-1",
            displayType: "APP_IPHONE_65",
            files: [imageURL]
        )

        #expect(uploaded == 1)
    }

    @Test func screenshotRejectedDuringProcessingIsRemovedAfterOldSetWasCleared() async throws {
        let (folder, file) = try Self.makeScreenshotFile()
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = URLSession(configuration: Self.stubConfiguration(routes: Self.screenshotSetRoutes(oldScreenshotID: "old-shot-1") + [
            { request in Self.emptyResponse(for: request, statusCode: 200) },   // PUT bytes
            { request in Self.emptyResponse(for: request, statusCode: 204) },   // PATCH uploaded
            { request in
                Self.deliveryStateResponse(
                    for: request,
                    id: "shot-1",
                    state: "FAILED",
                    errors: #"[{"code":"IMAGE_ALPHA_NOT_ALLOWED","description":"Alpha channel not allowed"}]"#
                )
            },
            { request in
                // The old set was already cleared; clean up the rejected new upload.
                #expect(request.httpMethod == "DELETE")
                #expect(request.url?.path == "/v1/appScreenshots/shot-1")
                return Self.emptyResponse(for: request, statusCode: 204)
            }
        ]))
        let client = Self.makeClient(session: session)

        do {
            _ = try await client.replaceScreenshots(localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [file])
            Issue.record("Expected processing failure")
        } catch let error as AppStoreConnectClientError {
            guard case .screenshotProcessingFailed(let details) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(details.contains("one.png"))
            #expect(details.contains("Alpha channel not allowed"))
        }
        #expect(StubURLProtocol.requestCount == 9)
    }

    @Test func failedBinaryUploadDeletesItsReservation() async throws {
        let (folder, file) = try Self.makeScreenshotFile()
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = URLSession(configuration: Self.stubConfiguration(routes: Self.screenshotSetRoutes(oldScreenshotID: nil) + [
            { request in Self.emptyResponse(for: request, statusCode: 403) },   // PUT bytes rejected
            { request in
                #expect(request.httpMethod == "DELETE")
                #expect(request.url?.path == "/v1/appScreenshots/shot-1")
                return Self.emptyResponse(for: request, statusCode: 204)
            }
        ]))
        let client = Self.makeClient(session: session)

        await #expect(throws: AppStoreConnectClientError.self) {
            _ = try await client.replaceScreenshots(localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [file])
        }
        #expect(StubURLProtocol.requestCount == 5)
    }

    @Test(arguments: [7, 9, 10])
    func replacementClearsExistingSetBeforeUploadingTenScreenshots(oldCount: Int) async throws {
        let (folder, file) = try Self.makeScreenshotFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try (0..<10).map { index in
            let url = folder.appending(path: "new-\(index).png")
            try FileManager.default.copyItem(at: file, to: url)
            return url
        }
        var routes = Array(Self.screenshotSetRoutes(oldScreenshotID: nil).prefix(1))
        routes.append { request in
            #expect(request.httpMethod == "GET")
            let items = (0..<oldCount).map { #"{"id":"old-\#($0)","type":"appScreenshots"}"# }.joined(separator: ",")
            return Self.jsonResponse(for: request, body: #"{"data":[\#(items)]}"#)
        }
        for index in 0..<oldCount {
            routes.append { request in
                #expect(request.httpMethod == "DELETE")
                #expect(request.url?.path == "/v1/appScreenshots/old-\(index)")
                return Self.emptyResponse(for: request, statusCode: 204)
            }
        }
        routes.append { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
            return Self.jsonResponse(for: request, body: #"{"data":[]}"#)
        }
        for index in 0..<10 {
            routes += [
                { request in
                    #expect(request.httpMethod == "POST")
                    #expect(request.url?.path == "/v1/appScreenshots")
                    return Self.jsonResponse(for: request, body: """
                    {"data":{"id":"new-\(index)","type":"appScreenshots","attributes":{
                    "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/new-\(index)","offset":0,"length":5,"requestHeaders":[]}]}}}
                    """)
                },
                { request in
                    #expect(request.httpMethod == "PUT")
                    #expect(request.url?.path == "/new-\(index)")
                    return Self.emptyResponse(for: request, statusCode: 200)
                },
                { request in
                    #expect(request.httpMethod == "PATCH")
                    #expect(request.url?.path == "/v1/appScreenshots/new-\(index)")
                    return Self.emptyResponse(for: request, statusCode: 204)
                }
            ]
        }
        routes += [
            { request in
                #expect(request.httpMethod == "GET")
                let items = (0..<10).map { #"{"id":"new-\#($0)","type":"appScreenshots","attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}"# }.joined(separator: ",")
                return Self.jsonResponse(for: request, body: #"{"data":[\#(items)]}"#)
            },
            { request in
                #expect(request.httpMethod == "PATCH")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/relationships/appScreenshots")
                let data = request.httpBody ?? request.httpBodyStream.map { Self.readStream($0) } ?? Data()
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let resources = try #require(body["data"] as? [[String: String]])
                #expect(resources.compactMap { $0["id"] } == (0..<10).map { "new-\($0)" })
                return Self.emptyResponse(for: request, statusCode: 204)
            }
        ]
        let count = routes.count
        let session = URLSession(configuration: Self.stubConfiguration(routes: routes))
        defer { session.invalidateAndCancel() }
        let uploaded = try await Self.makeClient(session: session).replaceScreenshots(
            localizationId: "loc-1", displayType: "APP_IPHONE_65", files: files
        )
        #expect(uploaded == 10)
        #expect(StubURLProtocol.requestCount == count)
    }

    @Test func deletionFailureStopsBeforeCreatingNewScreenshots() async throws {
        let (folder, file) = try Self.makeScreenshotFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let routes = Array(Self.screenshotSetRoutes(oldScreenshotID: "old-shot-1").prefix(2)) + [
            { request in
                #expect(request.httpMethod == "DELETE")
                return Self.emptyResponse(for: request, statusCode: 500)
            }
        ]
        let session = URLSession(configuration: Self.stubConfiguration(routes: routes))
        defer { session.invalidateAndCancel() }
        await #expect(throws: AppStoreConnectClientError.self) {
            _ = try await Self.makeClient(session: session).replaceScreenshots(
                localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [file]
            )
        }
        #expect(StubURLProtocol.requestCount == 3)
    }

    @Test(arguments: [true, false])
    func replacementWaitsForConfirmedEmptySet(eventuallyEmpty: Bool) async throws {
        let (folder, file) = try Self.makeScreenshotFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        var routes = Array(Self.screenshotSetRoutes(oldScreenshotID: "old-shot-1").prefix(3))
        for _ in 0..<(eventuallyEmpty ? 1 : 6) {
            routes.append { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                return Self.jsonResponse(for: request, body: #"{"data":[{"id":"old-shot-1","type":"appScreenshots"}]}"#)
            }
        }
        if eventuallyEmpty {
            routes += Array(Self.screenshotSetRoutes(oldScreenshotID: "old-shot-1").suffix(2))
            routes += [
                { request in
                    #expect(request.httpMethod == "PUT")
                    return Self.emptyResponse(for: request, statusCode: 200)
                },
                { request in
                    #expect(request.httpMethod == "PATCH")
                    return Self.emptyResponse(for: request, statusCode: 204)
                },
                { request in Self.deliveryStateResponse(for: request, id: "shot-1", state: "COMPLETE") }
            ]
        }
        let count = routes.count
        let session = URLSession(configuration: Self.stubConfiguration(routes: routes))
        defer { session.invalidateAndCancel() }
        let client = Self.makeClient(session: session)
        if eventuallyEmpty {
            #expect(try await client.replaceScreenshots(localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [file]) == 1)
        } else {
            await #expect(throws: AppStoreConnectClientError.screenshotDeletionNotConfirmed) {
                _ = try await client.replaceScreenshots(localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [file])
            }
        }
        #expect(StubURLProtocol.requestCount == count)
    }

    @Test func unreadableLocalFileStopsBeforeAnyRemoteRequest() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: []))
        defer { session.invalidateAndCancel() }
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
        await #expect(throws: (any Error).self) {
            _ = try await Self.makeClient(session: session).replaceScreenshots(
                localizationId: "loc-1", displayType: "APP_IPHONE_65", files: [missing]
            )
        }
        #expect(StubURLProtocol.requestCount == 0)
    }

    @Test func reviewSubmissionConflictWithoutReusableSubmissionKeepsAppleMessage() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/v1/reviewSubmissions")
                return Self.jsonResponse(
                    for: request,
                    statusCode: 409,
                    body: #"{"errors":[{"status":"409","code":"STATE_ERROR","title":"A build is required","detail":"Select a build before submitting."}]}"#
                )
            },
            { request in
                let query = request.url?.query ?? ""
                #expect(request.url?.path == "/v1/reviewSubmissions")
                #expect(query.contains("filter%5Bapp%5D=app-1") || query.contains("filter[app]=app-1"))
                return Self.jsonResponse(for: request, body: #"{"data":[]}"#)
            }
        ]))
        let client = Self.makeClient(session: session)

        do {
            _ = try await client.submitForReview(appId: "app-1", versionId: "v-1", platform: "IOS")
            Issue.record("Expected the 409 to surface")
        } catch let AppStoreConnectClientError.requestFailed(statusCode, message) {
            #expect(statusCode == 409)
            #expect(message.contains("Select a build before submitting."))
        }
    }

    @Test func reviewSubmissionConflictReusesUnsubmittedDraft() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                Self.jsonResponse(for: request, statusCode: 409, body: #"{"errors":[{"status":"409","title":"Conflict"}]}"#)
            },
            { request in
                // A rejected submission is listed first, but the never-submitted
                // draft is the one an interrupted attempt left behind.
                Self.jsonResponse(
                    for: request,
                    body: """
                    {"data":[
                      {"id":"rs-rejected","type":"reviewSubmissions","attributes":{"state":"UNRESOLVED_ISSUES","platform":"IOS","submittedDate":"2026-09-01T10:00:00Z"}},
                      {"id":"rs-draft","type":"reviewSubmissions","attributes":{"state":"READY_FOR_REVIEW","platform":"IOS"}}
                    ]}
                    """
                )
            },
            { request in
                #expect(request.url?.path == "/v1/reviewSubmissionItems")
                let body = request.httpBody ?? request.httpBodyStream.map { Self.readStream($0) } ?? Data()
                #expect(String(decoding: body, as: UTF8.self).contains("rs-draft"))
                return Self.jsonResponse(for: request, body: #"{"data":{"id":"item-1","type":"reviewSubmissionItems"}}"#)
            },
            { request in
                #expect(request.httpMethod == "PATCH")
                #expect(request.url?.path == "/v1/reviewSubmissions/rs-draft")
                return Self.jsonResponse(for: request, body: #"{"data":{"id":"rs-draft","type":"reviewSubmissions","attributes":{"state":"WAITING_FOR_REVIEW"}}}"#)
            }
        ]))
        let client = Self.makeClient(session: session)

        let state = try await client.submitForReview(appId: "app-1", versionId: "v-1", platform: "IOS")
        #expect(state == "WAITING_FOR_REVIEW")
    }

    @Test func reviewItemConflictForAnotherVersionIsNotTreatedAsAttached() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                Self.jsonResponse(for: request, body: #"{"data":{"id":"rs-1","type":"reviewSubmissions","attributes":{"state":"READY_FOR_REVIEW"}}}"#)
            },
            { request in
                Self.jsonResponse(
                    for: request,
                    statusCode: 409,
                    body: #"{"errors":[{"status":"409","title":"Missing screenshots","detail":"Upload screenshots for every required size."}]}"#
                )
            },
            { request in
                #expect(request.url?.path == "/v1/reviewSubmissions/rs-1/items")
                return Self.jsonResponse(
                    for: request,
                    body: #"{"data":[{"id":"item-9","type":"reviewSubmissionItems","relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"other-version"}}}}]}"#
                )
            }
        ]))
        let client = Self.makeClient(session: session)

        do {
            _ = try await client.submitForReview(appId: "app-1", versionId: "v-1", platform: "IOS")
            Issue.record("Expected the item conflict to surface")
        } catch let AppStoreConnectClientError.requestFailed(_, message) {
            #expect(message.contains("Upload screenshots for every required size."))
        }
        // No submit PATCH was sent.
        #expect(StubURLProtocol.requestCount == 3)
    }

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    @Test func screenshotSetsAreFetchedWithTheirScreenshotsInOneRequest() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                #expect(request.url?.path == "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets")
                #expect(request.url?.query?.contains("include=appScreenshots") == true)
                return Self.jsonResponse(
                    for: request,
                    body: """
                    {
                      "data": [{
                        "id": "set-1", "type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": "APP_IPHONE_65"},
                        "relationships": {"appScreenshots": {"data": [
                          {"type": "appScreenshots", "id": "shot-2"},
                          {"type": "appScreenshots", "id": "shot-1"}
                        ]}}
                      }],
                      "included": [
                        {"id": "shot-1", "type": "appScreenshots", "attributes": {"fileName": "one.png", "fileSize": 10,
                          "imageAsset": {"templateUrl": "https://img.example.test/a/{w}x{h}bb.{f}", "width": 1242, "height": 2688}}},
                        {"id": "shot-2", "type": "appScreenshots", "attributes": {"fileName": "two.png", "fileSize": 20}}
                      ]
                    }
                    """
                )
            }
        ]))
        let client = Self.makeClient(session: session)

        let sets = try await client.fetchScreenshotSets(localizationId: "loc-1")

        #expect(StubURLProtocol.requestCount == 1)
        #expect(sets.first?.slot == .iPhone65)
        // Relationship order is the display order.
        #expect(sets.first?.screenshots.map(\.id) == ["shot-2", "shot-1"])
        let thumbnail = sets.first?.screenshots.last?.imageURL?.absoluteString
        #expect(thumbnail == "https://img.example.test/a/240x519bb.jpg")
        #expect(sets.first?.screenshots.last?.width == 1242)
    }

    @Test func visionMatchingSendsEveryCandidateInBatchesWithoutFilePaths() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "shipnotes-vision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let assets = try (1...13).map { index -> ScreenshotAsset in
            let url = folder.appending(path: "shot-\(index).png")
            try Self.writeTinyPNG(to: url)
            return ScreenshotAsset(
                url: url, relativePath: "upload/shot-\(index).png",
                size: ScreenshotPixelSize(width: 1320, height: 2868),
                locale: nil, deviceSlot: .iPhone69, status: .ready, contentHash: nil
            )
        }

        @Sendable func answer(_ promptID: String, locale: String) -> String {
            let content = #"{"assignments":[{"asset_id":"\#(promptID)","locale":"\#(locale)","confidence":0.9}]}"#
            let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
            return #"{"choices":[{"message":{"content":"\#(escaped)"}}]}"#
        }
        let folderPath = folder.path
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                let body = String(decoding: request.httpBody ?? request.httpBodyStream.map { Self.readStream($0) } ?? Data(), as: UTF8.self)
                #expect(body.components(separatedBy: "base64,").count - 1 == 12)
                #expect(!body.contains(folderPath))
                return Self.jsonResponse(for: request, body: answer("screenshot-1", locale: "ja"))
            },
            { request in
                let body = String(decoding: request.httpBody ?? request.httpBodyStream.map { Self.readStream($0) } ?? Data(), as: UTF8.self)
                #expect(body.components(separatedBy: "base64,").count - 1 == 1)
                return Self.jsonResponse(for: request, body: answer("screenshot-13", locale: "ko"))
            }
        ]))
        let service = OpenAIScreenshotVisionAIService(
            urlSession: session,
            baseURL: URL(string: "https://vision.example.test/v1")!,
            model: "test-model",
            cachedKey: "test-key"
        )

        let assignments = try await service.classifyScreenshotLocales(assets: assets, knownLocales: ["ja", "ko"], appName: nil)

        #expect(StubURLProtocol.requestCount == 2)
        #expect(assignments.map(\.assetID) == [assets[0].id, assets[12].id])
        #expect(assignments.map(\.locale) == ["ja", "ko"])
    }

    private static func writeTinyPNG(to url: URL) throws {
        let context = CGContext(
            data: nil, width: 4, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 8))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func fetchingVersionLocalizationsDoesNotRequestSubtitle() async throws {
        let session = URLSession(configuration: Self.stubConfiguration(routes: [
            { request in
                let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
                let fieldItem = components.queryItems?.first(where: { $0.name == "fields[appStoreVersionLocalizations]" })
                let fields = try #require(fieldItem?.value)
                #expect(!fields.split(separator: ",").contains("subtitle"))
                return Self.jsonResponse(for: request, body: #"{"data":[]}"#)
            }
        ]))
        let credentials = AppStoreConnectCredentials(name: "Test", issuerId: "issuer", keyId: "key", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
        let client = AppStoreConnectClient(credentials: credentials, session: session)
        #expect(try await client.fetchLocalizations(versionId: "v-1").isEmpty)
    }

    private static func stubConfiguration(routes: [StubURLProtocol.Route]) -> URLSessionConfiguration {
        StubURLProtocol.reset(routes: routes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    private static func jsonResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func deliveryStateResponse(
        for request: URLRequest,
        id: String,
        state: String,
        errors: String = "[]"
    ) -> (HTTPURLResponse, Data) {
        jsonResponse(
            for: request,
            body: """
            {"data":[{"id":"\(id)","type":"appScreenshots","attributes":{"assetDeliveryState":{"state":"\(state)","errors":\(errors)}}}]}
            """
        )
    }

    private static func makeClient(session: URLSession) -> AppStoreConnectClient {
        let credentials = AppStoreConnectCredentials(
            name: "Test",
            issuerId: "issuer-123",
            keyId: "KEY1234567",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
        )
        return AppStoreConnectClient(credentials: credentials, session: session)
    }

    private static func makeScreenshotFile() throws -> (folder: URL, file: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "shipnotes-asc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "one.png")
        try Data("image".utf8).write(to: file)
        return (folder, file)
    }

    private static func screenshotSetRoutes(oldScreenshotID: String?) -> [StubURLProtocol.Route] {
        var routes: [StubURLProtocol.Route] = [
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets")
                return jsonResponse(for: request, body: #"{"data":[{"id":"set-1","type":"appScreenshotSets","attributes":{"screenshotDisplayType":"APP_IPHONE_65"}}]}"#)
            },
            { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                let old = oldScreenshotID.map {
                    #"{"id":"\#($0)","type":"appScreenshots","attributes":{"fileName":"old.png","fileSize":1}}"#
                } ?? ""
                return jsonResponse(for: request, body: #"{"data":[\#(old)]}"#)
            }
        ]
        if let oldScreenshotID {
            routes += [
                { request in
                    #expect(request.httpMethod == "DELETE")
                    #expect(request.url?.path == "/v1/appScreenshots/\(oldScreenshotID)")
                    return emptyResponse(for: request, statusCode: 204)
                },
                { request in
                    #expect(request.httpMethod == "GET")
                    #expect(request.url?.path == "/v1/appScreenshotSets/set-1/appScreenshots")
                    return jsonResponse(for: request, body: #"{"data":[]}"#)
                }
            ]
        }
        routes.append { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/appScreenshots")
            return jsonResponse(for: request, body: """
            {"data":{"id":"shot-1","type":"appScreenshots","attributes":{"fileName":"one.png","fileSize":5,
            "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/shot-1","offset":0,"length":5,"requestHeaders":[]}]}}}
            """)
        }
        return routes
    }

    private static func emptyResponse(
        for request: URLRequest,
        statusCode: Int
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (response, Data())
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Route = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) private static var routes: [Route] = []
    nonisolated(unsafe) private static var requestsStarted = 0
    private static let lock = NSLock()

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestsStarted
    }

    static func reset(routes: [Route]) {
        lock.lock()
        defer { lock.unlock() }
        self.routes = routes
        requestsStarted = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.nextResponse(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func nextResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }
        requestsStarted += 1
        guard !routes.isEmpty else {
            throw NSError(
                domain: "ShipNotesTests.StubURLProtocol",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No stub route for \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"]
            )
        }
        return try routes.removeFirst()(request)
    }
}

@Suite("AppStoreConnect retry policy")
struct AppStoreConnectRetryTests {
    @Test func rateLimitRetriesForAnyMethod() {
        // 429 = rejected before processing, so retrying is safe even for writes.
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 429, method: "POST"))
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 429, method: "PATCH"))
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 429, method: "GET"))
    }

    @Test func serverErrorsRetryOnlyForIdempotentMethods() {
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 503, method: "GET"))
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 503, method: "PUT"))
        // Retrying a POST/PATCH/DELETE on a 5xx could duplicate-create,
        // double-submit, or 404 a second delete.
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 503, method: "POST") == false)
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 500, method: "DELETE") == false)
    }

    @Test func nonRetryableStatusesAreNotRetried() {
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 200, method: "GET") == false)
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 404, method: "GET") == false)
        #expect(AppStoreConnectClient.shouldRetry(statusCode: 401, method: "GET") == false)
    }

    @Test func transientNetworkErrorsRetryOnlyForIdempotentMethods() {
        #expect(AppStoreConnectClient.shouldRetry(urlError: URLError(.timedOut), method: "GET"))
        #expect(AppStoreConnectClient.shouldRetry(urlError: URLError(.timedOut), method: "PUT"))
        #expect(AppStoreConnectClient.shouldRetry(urlError: URLError(.timedOut), method: "POST") == false)
        // Non-transient errors never retry.
        #expect(AppStoreConnectClient.shouldRetry(urlError: URLError(.badURL), method: "GET") == false)
    }

    @Test func retryAfterHeaderIsHonored() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.appstoreconnect.apple.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "2"]
        ))
        // 2 seconds → 2_000_000_000 ns exactly (header wins over backoff).
        #expect(HTTPRetryPolicy.retryDelayNanos(attempt: 1, response: response) == 2_000_000_000)
    }

    @Test func rateLimitResetAfterHeaderIsHonored() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.ads.apple.com/v1/campaigns/query")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["RateLimit-Reset-After": "3"]
        ))
        #expect(HTTPRetryPolicy.retryDelayNanos(attempt: 1, response: response) == 3_000_000_000)
    }

    @Test func retryAfterHeaderIsCappedAndMalformedValuesFallBackSafely() throws {
        let capped = try #require(HTTPURLResponse(
            url: URL(string: "https://api.appstoreconnect.apple.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "600"]
        ))
        #expect(HTTPRetryPolicy.retryDelayNanos(attempt: 1, response: capped) == 120_000_000_000)

        for invalidValue in ["-1", "nan"] {
            let malformed = try #require(HTTPURLResponse(
                url: URL(string: "https://api.appstoreconnect.apple.com")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": invalidValue]
            ))
            let nanos = HTTPRetryPolicy.retryDelayNanos(attempt: 1, response: malformed)
            #expect(nanos > 0)
            #expect(nanos <= 30_000_000_000)
        }
    }

    @Test func backoffStaysWithinBounds() {
        // No header → exponential backoff with jitter, capped at 30s.
        for attempt in 1...6 {
            let nanos = HTTPRetryPolicy.retryDelayNanos(attempt: attempt, response: nil)
            #expect(nanos > 0)
            #expect(nanos <= 30_000_000_000)
        }
    }

    // MARK: Localization update request URL handling

    private func encodeAttributes(_ body: ASCLocalizationUpdateRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let resource = try #require(object["data"] as? [String: Any])
        return try #require(resource["attributes"] as? [String: Any])
    }

    @Test func versionLocalizationRequestExcludesAppInfoFields() throws {
        let body = ASCLocalizationUpdateRequest(id: "loc-1", metadata: StoreMetadataFields(
            subtitle: "Local subtitle", description: "Description", privacyPolicyURL: "https://example.com/privacy"
        ))
        let attributes = try encodeAttributes(body)
        #expect(attributes["subtitle"] == nil)
        #expect(attributes["privacyPolicyUrl"] == nil)
        #expect(attributes["description"] as? String == "Description")
        #expect(!StoreCopyField.subtitle.isVersionLocalizationField)
        #expect(!StoreCopyField.privacyPolicyURL.isVersionLocalizationField)
    }

    @Test func localizationUpdateRequestOmitsBlankURLAttributes() throws {
        // Apple rejects "" URL attributes with a 409 ENTITY_ERROR_ATTRIBUTE_TYPE;
        // an omitted key leaves the remote value untouched instead.
        let body = ASCLocalizationUpdateRequest(
            id: "loc-1",
            metadata: StoreMetadataFields(
                description: "Updated",
                keywords: "kw",
                promotionalText: "promo",
                supportURL: "",
                marketingURL: "   "
            )
        )
        let attributes = try encodeAttributes(body)
        #expect(attributes["supportUrl"] == nil)
        #expect(attributes["marketingUrl"] == nil)
        #expect(attributes["description"] as? String == "Updated")
    }

    @Test func localizationUpdateRequestTrimsURLAttributes() throws {
        let body = ASCLocalizationUpdateRequest(
            id: "loc-1",
            metadata: StoreMetadataFields(supportURL: "  https://example.com/support ")
        )
        let attributes = try encodeAttributes(body)
        #expect(attributes["supportUrl"] as? String == "https://example.com/support")
    }

    @Test func localizationFieldUpdateRequestOmitsBlankURLValue() throws {
        let body = ASCLocalizationUpdateRequest(id: "loc-1", field: .supportURL, value: " ")
        let attributes = try encodeAttributes(body)
        #expect(attributes["supportUrl"] == nil)
        #expect(attributes["description"] == nil)
    }

    @Test func ascErrorItemNamesTheFailingAttribute() throws {
        let json = """
        {"errors":[{"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.TYPE","title":"The request failed","detail":"must be a valid RFC 3986 URI","source":{"pointer":"/data/attributes/supportUrl"}}]}
        """
        let decoded = try JSONDecoder().decode(ASCErrorResponse.self, from: Data(json.utf8))
        let message = try #require(decoded.errors.first?.displayMessage)
        #expect(message.contains("supportUrl"))
        #expect(message.contains("ENTITY_ERROR.ATTRIBUTE.TYPE"))
    }
}
