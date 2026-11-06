import Foundation
import Testing
@testable import ShipNotes

@Suite("Responses API transport", .serialized)
struct ResponsesAPITransportTests {
    @Test func endpointSelectionPreservesPrefixesAndSwitchesCompleteEndpoints() {
        let cases: [(String, OpenAIAPIFormat, String)] = [
            ("https://api.openai.com", .responses, "https://api.openai.com/v1/responses"),
            ("https://api.deepseek.com/", .responses, "https://api.deepseek.com/responses"),
            ("https://proxy.example", .responses, "https://proxy.example/v1/responses"),
            ("https://proxy.example/prefix", .responses, "https://proxy.example/prefix/v1/responses"),
            ("https://proxy.example/prefix/v1/", .responses, "https://proxy.example/prefix/v1/responses"),
            (
                "https://proxy.example/prefix/v1/chat/completions/", .responses,
                "https://proxy.example/prefix/v1/responses"
            ),
            (
                "https://proxy.example/prefix/responses", .chatCompletions,
                "https://proxy.example/prefix/chat/completions"
            ),
            (
                "https://proxy.example/prefix/v1/responses", .chatCompletions,
                "https://proxy.example/prefix/v1/chat/completions"
            ),
            ("https://proxy.example/prefix/responses", .responses, "https://proxy.example/prefix/responses"),
            (
                "https://proxy.example/prefix/chat/completions", .chatCompletions,
                "https://proxy.example/prefix/chat/completions"
            ),
            (
                "https://proxy.example/tenant%2Fblue/v1/chat/completions/?route=fixture#anchor", .responses,
                "https://proxy.example/tenant%2Fblue/v1/responses?route=fixture#anchor"
            ),
        ]
        for (input, format, expected) in cases {
            #expect(AIEndpointResolver.openAI(from: URL(string: input)!, format: format).absoluteString == expected)
        }
        #expect(
            AIEndpointResolver.openAIChatCompletions(from: URL(string: "https://proxy.example/v1")!).path
                == "/v1/chat/completions")
    }

    @Test func responsesRequestConvertsJSONAndImagesWithoutReorderingOrRetainingInput() throws {
        let chat: [String: Any] = [
            "model": "fixture-model", "temperature": 0.8, "max_tokens": 10, "max_completion_tokens": 42,
            "response_format": ["type": "json_object"], "store": true,
            "messages": [
                ["role": "system", "content": "Return JSON"],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "asset-1"],
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,ZmFrZQ==", "detail": "low"],
                        ],
                        ["type": "text", "text": "asset-2"],
                    ],
                ],
            ],
        ]
        let request = OpenAIAPIAdapter.requestBody(fromChatBody: chat, format: .responses)
        #expect(request["messages"] == nil)
        #expect(request["response_format"] == nil)
        #expect(request["max_tokens"] == nil)
        #expect(request["max_completion_tokens"] == nil)
        #expect(request["temperature"] == nil)
        #expect(request["store"] as? Bool == false)
        #expect(request["max_output_tokens"] as? Int == 42)
        #expect((request["text"] as? [String: Any])?["format"] as? [String: String] == ["type": "json_object"])
        let input = try #require(request["input"] as? [[String: Any]])
        #expect(input[0]["role"] as? String == "system")
        #expect(input[0]["content"] as? String == "Return JSON")
        let blocks = try #require(input[1]["content"] as? [[String: Any]])
        #expect(blocks.compactMap { $0["type"] as? String } == ["input_text", "input_image", "input_text"])
        #expect(blocks[1]["image_url"] as? String == "data:image/png;base64,ZmFrZQ==")
        #expect(blocks[1]["detail"] as? String == "low")
        #expect(blocks[2]["text"] as? String == "asset-2")

        let unchanged = OpenAIAPIAdapter.requestBody(fromChatBody: chat, format: .chatCompletions)
        #expect(
            try JSONSerialization.data(withJSONObject: unchanged, options: .sortedKeys)
                == JSONSerialization.data(withJSONObject: chat, options: .sortedKeys))
    }

    @Test func chatJSONSchemaIsFlattenedForResponsesTextFormat() throws {
        let result = OpenAIAPIAdapter.requestBody(
            fromChatBody: [
                "messages": [["role": "user", "content": "Return JSON"]],
                "response_format": [
                    "type": "json_schema",
                    "json_schema": [
                        "name": "fixture", "strict": true, "schema": ["type": "object"],
                    ],
                ],
            ], format: .responses)
        let format = try #require((result["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "fixture")
        #expect(format["strict"] as? Bool == true)
        #expect(format["json_schema"] == nil)
        #expect(format["schema"] as? [String: String] == ["type": "object"])
    }

    @Test func translationUsesResponsesWireSchemaAndNestedOutputText() async throws {
        let session = session(reply: completedOutput(#"{"translated_text":"Fixture translation"}"#)) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
            let body = try Self.requestJSON(request)
            #expect(body["model"] as? String == "fixture-reasoning-model")
            #expect(body["messages"] == nil && body["temperature"] == nil)
            #expect(body["store"] as? Bool == false)
            let input = try #require(body["input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["system", "user"])
            #expect((body["text"] as? [String: Any])?["format"] as? [String: String] == ["type": "json_object"])
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            baseURL: URL(string: "https://api.deepseek.com")!, model: "fixture-reasoning-model",
            apiFormat: .responses, cachedKey: "fixture-key")
        #expect(
            try await service.translate(text: "Fixture", fromLocale: "en-US", toLocale: "ja", glossary: [:])
                == "Fixture translation")
    }

    @Test func releaseNotesParseThroughResponsesWithoutSDKConvenienceField() async throws {
        let session = session(
            reply:
                #"{"object":"response","status":"completed","output":[{"type":"reasoning","summary":[{"text":"not the answer"}]},{"type":"message","content":[{"type":"output_text","text":"{\"locales\":{"},{"type":"output_text","text":"\"en-US\":\"Fixture release\"}}"}]}]}"#
        ) { request in
            #expect(request.url?.path == "/gateway/v1/responses")
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            baseURL: URL(string: "https://proxy.example/gateway/v1/chat/completions")!,
            apiFormat: .responses, cachedKey: "fixture-key")
        let locales = try await service.parseReleaseNotes(
            text: "Fixture", currentVersion: "1.0", knownRemoteLocales: ["en-US"])
        #expect(locales == ["en-US": "Fixture release"])
    }

    @Test func optimizationPreservesOriginalURLsInResponsesMode() async throws {
        let session = session(
            reply: completedOutput(
                #"{"description":"Optimized","keywords":"fixture","supportURL":"https://invented.example/support","marketingURL":"https://invented.example","privacyPolicyURL":"https://invented.example/privacy"}"#
            ))
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            apiFormat: .responses, cachedKey: "fixture-key")
        let original = StoreMetadataFields(
            description: "Original", supportURL: "https://original.example/support",
            marketingURL: "https://original.example", privacyPolicyURL: "https://original.example/privacy")
        let optimized = try await service.optimizeStoreMetadata(
            metadata: original, locale: "en-US", appName: "Fixture App", versionString: "1.0")
        #expect(optimized.description == "Optimized")
        #expect(optimized.supportURL == original.supportURL)
        #expect(optimized.marketingURL == original.marketingURL)
        #expect(optimized.privacyPolicyURL == original.privacyPolicyURL)
    }

    @Test func storeMetadataResponsesReturnsEveryLocaleUsingJSONInput() async throws {
        let session = session(
            reply: completedOutput(
                #"{"locales":{"en-US":{"description":"Fixture description","keywords":"fixture,store","supportURL":"https://fixture.example/help"},"ja":{"description":"テストの説明","promotional_text":"テストの告知"}}}"#
            )
        ) { request in
            #expect(request.url?.path == "/catalog/responses")
            let body = try Self.requestJSON(request)
            #expect(body["store"] as? Bool == false)
            #expect(body["messages"] == nil && body["temperature"] == nil)
            #expect((body["text"] as? [String: Any])?["format"] as? [String: String] == ["type": "json_object"])
            let input = try #require(body["input"] as? [[String: Any]])
            #expect(input.compactMap { $0["role"] as? String } == ["system", "user"])
            #expect(input.last?["content"] as? String != nil)
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            baseURL: URL(string: "https://proxy.example/catalog/responses")!,
            apiFormat: .responses, cachedKey: "fixture-key")
        let locales = try await service.parseStoreMetadata(
            text: "Fixture metadata source", defaultLocale: "en-US", knownRemoteLocales: ["en-US", "ja"],
            appName: "Fixture App", versionString: "1.0")
        #expect(Set(locales.keys) == ["en-US", "ja"])
        #expect(locales["en-US"]?.description == "Fixture description")
        #expect(locales["en-US"]?.supportURL == "https://fixture.example/help")
        #expect(locales["ja"]?.description == "テストの説明")
        #expect(locales["ja"]?.promotionalText == "テストの告知")
    }

    @Test(arguments: ResponsesErrorFixture.allCases)
    func incompleteFailedRefusedAndEmptyResponsesAreNeverAccepted(_ fixture: ResponsesErrorFixture) async throws {
        let session = session(reply: fixture.json)
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            apiFormat: .responses, cachedKey: "fixture-key")
        do {
            _ = try await service.translate(text: "Fixture", fromLocale: "en-US", toLocale: "ja", glossary: [:])
            Issue.record("Expected \(fixture) to fail")
        } catch let error as AIServiceError {
            switch (fixture, error) {
            case (.truncated, .outputTruncated), (.refused, .requestRejected), (.filtered, .requestRejected): break
            case (.failed, .invalidResponse), (.incomplete, .invalidResponse), (.queued, .invalidResponse),
                (.empty, .invalidResponse), (.reasoningOnly, .invalidResponse), (.sdkFieldOnly, .invalidResponse),
                (.messageIncomplete, .invalidResponse):
                break
            default: Issue.record("Unexpected error \(error) for \(fixture)")
            }
        }
    }

    @Test func defaultChatProtocolStillUsesMessagesAndChoices() async throws {
        let session = session(reply: #"{"choices":[{"message":{"content":"{\"translated_text\":\"Classic\"}"}}]}"#) {
            request in
            #expect(request.url?.path == "/v1/chat/completions")
            let body = try Self.requestJSON(request)
            #expect(body["messages"] != nil)
            #expect(body["input"] == nil)
            #expect(body["response_format"] as? [String: String] == ["type": "json_object"])
            #expect(body["temperature"] as? Int == 0)
        }
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(
            keychainStore: InMemoryAIKeychainStore(), urlSession: session,
            baseURL: URL(string: "https://proxy.example/v1/responses")!, cachedKey: "fixture-key")
        #expect(
            try await service.translate(text: "Fixture", fromLocale: "en-US", toLocale: "ja", glossary: [:])
                == "Classic")
    }

    private func session(reply: String, check: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> URLSession
    {
        ResponsesTransportStub.setHandler { request in
            try check(request)
            return Data(reply.utf8)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponsesTransportStub.self]
        return URLSession(configuration: configuration)
    }

    private func completedOutput(_ text: String) -> String {
        let object: [String: Any] = [
            "object": "response", "status": "completed",
            "output": [
                ["type": "message", "status": "completed", "content": [["type": "output_text", "text": text]]]
            ],
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private static func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

enum ResponsesErrorFixture: CaseIterable, Sendable {
    case truncated, incomplete, failed, refused, filtered, queued, empty, reasoningOnly, sdkFieldOnly, messageIncomplete
    var json: String {
        switch self {
        case .truncated:
            return
                #"{"object":"response","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#
        case .incomplete: return #"{"object":"response","status":"incomplete","output":[]}"#
        case .failed:
            return #"{"object":"response","status":"failed","error":{"message":"Fixture failure"},"output":[]}"#
        case .refused:
            return
                #"{"object":"response","status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"Fixture refusal"}]}]}"#
        case .filtered:
            return
                #"{"object":"response","status":"incomplete","incomplete_details":{"reason":"content_filter"},"output":[]}"#
        case .queued: return #"{"object":"response","status":"queued","output":[]}"#
        case .empty:
            return
                #"{"object":"response","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"   "}]}]}"#
        case .reasoningOnly:
            return
                #"{"object":"response","status":"completed","output":[{"type":"reasoning","content":[{"type":"output_text","text":"not the answer"}]}]}"#
        case .sdkFieldOnly:
            return #"{"object":"response","status":"completed","output_text":"not a wire output","output":[]}"#
        case .messageIncomplete:
            return
                #"{"object":"response","status":"completed","output":[{"type":"message","status":"incomplete","content":[{"type":"output_text","text":"partial"}]}]}"#
        }
    }
}

private final class ResponsesTransportStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> Data)?
    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> Data) {
        lock.withLock { self.handler = handler }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try #require(Self.lock.withLock { Self.handler })
            let data = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
