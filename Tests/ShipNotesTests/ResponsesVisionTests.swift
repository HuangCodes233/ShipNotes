import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShipNotes

@Suite("Responses vision transport")
struct ResponsesVisionTests {
    @Test func responsesConvertsImagesAndReadsMessageAfterReasoning() async throws {
        let fixture = try VisionImageFixture(count: 1)
        defer { fixture.remove() }
        let requests = VisionRequestRecorder()
        let endpoint = VisionHTTPFixture(recorder: requests) { request in
            try Self.assignmentResponse(for: request, responses: true)
        }
        defer { endpoint.close() }
        let keys = VisionFixtureKeyStore(text: "text-fixture", vision: "vision-fixture")
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: keys, urlSession: endpoint.session,
            baseURL: endpoint.baseURL.appendingPathComponent("v1/chat/completions"),
            model: "fixture-vision-model", apiFormat: .responses)
        let assignments = try await service.classifyScreenshotLocales(
            assets: fixture.assets, knownLocales: ["en-US", "ja"], appName: "Fixture")
        #expect(assignments.map(\.assetID) == fixture.assets.map(\.id))
        let request = try #require(requests.values.first)
        #expect(request.url?.path == "/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer vision-fixture")
        let body = try Self.body(request)
        #expect(body["model"] as? String == "fixture-vision-model")
        #expect(body["store"] as? Bool == false)
        #expect(body["max_output_tokens"] as? Int == 4096)
        #expect(body["messages"] == nil)
        #expect(body["max_tokens"] == nil)
        #expect(body["temperature"] == nil)
        #expect(body["response_format"] == nil)
        let textOptions = try #require(body["text"] as? [String: Any])
        let format = try #require(textOptions["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
        let content = try Self.content(body, responses: true)
        #expect(content.compactMap { $0["type"] as? String } == ["input_text", "input_text", "input_image"])
        let image = try #require(content.last)
        #expect(image["detail"] as? String == "low")
        let imageURL = try #require(image["image_url"] as? String)
        let prefix = "data:image/jpeg;base64,"
        #expect(imageURL.hasPrefix(prefix))
        let imageBytes = try #require(Data(base64Encoded: String(imageURL.dropFirst(prefix.count))))
        let source = try #require(CGImageSourceCreateWithData(imageBytes as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 512)
        #expect(decoded.height == 384)
        let requestText = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(requestText.contains("screenshot-1"))
        #expect(requestText.contains("relative_path"))
        #expect(!requestText.contains(fixture.folder.path))
        #expect(keys.readRoles.allSatisfy { $0 == .vision })
    }

    @Test func responsesClassifiesEveryAssetAcrossBatchesAndIgnoresInventedIDs() async throws {
        let fixture = try VisionImageFixture(count: 13)
        defer { fixture.remove() }
        let requests = VisionRequestRecorder()
        let endpoint = VisionHTTPFixture(recorder: requests) { request in
            try Self.assignmentResponse(for: request, responses: true, addInventedID: true)
        }
        defer { endpoint.close() }
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: VisionFixtureKeyStore(), urlSession: endpoint.session, baseURL: endpoint.baseURL,
            apiFormat: .responses, cachedKey: "cached-vision-fixture")
        let assignments = try await service.classifyScreenshotLocales(
            assets: fixture.assets, knownLocales: ["en-US"], appName: nil)
        #expect(Set(assignments.map(\.assetID)) == Set(fixture.assets.map(\.id)))
        #expect(assignments.count == 13)
        let imageCounts = try requests.values.map { request in
            try Self.content(Self.body(request), responses: true).filter { $0["type"] as? String == "input_image" }
                .count
        }
        #expect(imageCounts == [12, 1])
    }

    @Test func defaultChatCompletionsRemainsCompatible() async throws {
        let fixture = try VisionImageFixture(count: 1)
        defer { fixture.remove() }
        let requests = VisionRequestRecorder()
        let endpoint = VisionHTTPFixture(recorder: requests) { request in
            try Self.assignmentResponse(for: request, responses: false)
        }
        defer { endpoint.close() }
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: VisionFixtureKeyStore(), urlSession: endpoint.session, baseURL: endpoint.baseURL,
            cachedKey: "cached-vision-fixture")
        let result = try await service.classifyScreenshotLocales(
            assets: fixture.assets, knownLocales: ["en-US"], appName: nil)
        #expect(result.count == 1)
        let request = try #require(requests.values.first)
        #expect(request.url?.path == "/v1/chat/completions")
        let body = try Self.body(request)
        #expect(body["input"] == nil)
        #expect(body["max_tokens"] as? Int == 4096)
        let image = try #require(try Self.content(body, responses: false).last)
        #expect(image["type"] as? String == "image_url")
        #expect((image["image_url"] as? [String: Any])?["detail"] as? String == "low")
    }

    @Test(arguments: VisionResponseFailure.allCases)
    func invalidResponsesAreRejectedBeforeReturningAssignments(_ failure: VisionResponseFailure) async throws {
        let fixture = try VisionImageFixture(count: 1)
        defer { fixture.remove() }
        let response = try Self.failureResponse(failure)
        let endpoint = VisionHTTPFixture(recorder: VisionRequestRecorder()) { _ in response }
        defer { endpoint.close() }
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: VisionFixtureKeyStore(), urlSession: endpoint.session, baseURL: endpoint.baseURL,
            apiFormat: .responses, cachedKey: "vision-fixture")
        do {
            _ = try await service.classifyScreenshotLocales(
                assets: fixture.assets, knownLocales: ["en-US"], appName: nil)
            Issue.record("Expected the provider response to be rejected")
        } catch let error as AIServiceError {
            switch (failure, error) {
            case (.incomplete, .outputTruncated), (.refusal, .requestRejected),
                (.failed, .invalidResponse), (.empty, .invalidResponse):
                break
            default: Issue.record("Unexpected AI error: \(error)")
            }
        }
    }

    @Test func textKeyCannotAuthenticateTheVisionProfile() async throws {
        let requests = VisionRequestRecorder()
        let endpoint = VisionHTTPFixture(recorder: requests) { _ in Data() }
        defer { endpoint.close() }
        let keys = VisionFixtureKeyStore(text: "text-only-fixture")
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: keys, urlSession: endpoint.session, baseURL: endpoint.baseURL, apiFormat: .responses)
        #expect(service.isConfigured == false)
        do {
            try await service.testConnection()
            Issue.record("Expected a missing vision key")
        } catch AIServiceError.missingAPIKey {}
        #expect(requests.values.isEmpty)
        #expect(keys.readRoles.allSatisfy { $0 == .vision })
    }

    @Test(arguments: [OpenAIAPIFormat.chatCompletions, .responses])
    func openAIConnectionTestsUseOnlyTheSavedVisionKeyAndNoImages(_ format: OpenAIAPIFormat) async throws {
        let requests = VisionRequestRecorder()
        let response = try Self.textResponse("OK", responses: format == .responses)
        let endpoint = VisionHTTPFixture(recorder: requests) { _ in response }
        defer { endpoint.close() }
        let keys = VisionFixtureKeyStore(text: "text-fixture", vision: "vision-fixture")
        let service = OpenAIScreenshotVisionAIService(
            keychainStore: keys, urlSession: endpoint.session, baseURL: endpoint.baseURL,
            model: "saved-vision-model", apiFormat: format)
        try await service.testConnection()
        let request = try #require(requests.values.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer vision-fixture")
        let body = try Self.body(request)
        #expect(body["model"] as? String == "saved-vision-model")
        #expect(
            body[format == .responses ? "max_output_tokens" : "max_tokens"] as? Int
                == (format == .responses ? 4096 : 256))
        let data = try #require(request.httpBody)
        let serialized = String(decoding: data, as: UTF8.self)
        #expect(!serialized.contains("input_image"))
        #expect(!serialized.contains("image_url"))
        #expect(!serialized.contains("data:image"))
        #expect(keys.readRoles == [.vision])
    }

    @Test func anthropicConnectionTestUsesTheVisionProfileWithoutImages() async throws {
        let requests = VisionRequestRecorder()
        let response = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "OK"]], "stop_reason": "end_turn",
        ])
        let endpoint = VisionHTTPFixture(recorder: requests) { _ in response }
        defer { endpoint.close() }
        let keys = VisionFixtureKeyStore(text: "text-fixture", vision: "vision-fixture")
        let service = AnthropicScreenshotVisionAIService(
            keychainStore: keys, urlSession: endpoint.session, baseURL: endpoint.baseURL, model: "saved-vision-model")
        try await service.testConnection()
        let request = try #require(requests.values.first)
        #expect(request.url?.path == "/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "vision-fixture")
        let serialized = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!serialized.contains("\"image\""))
        #expect(keys.readRoles == [.vision])
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func content(_ body: [String: Any], responses: Bool) throws -> [[String: Any]] {
        let messages = try #require(body[responses ? "input" : "messages"] as? [[String: Any]])
        return try #require(messages.first?["content"] as? [[String: Any]])
    }

    private static func assignmentResponse(
        for request: URLRequest, responses: Bool, addInventedID: Bool = false
    ) throws -> Data {
        let content = try content(body(request), responses: responses)
        var ids = content.compactMap { $0["text"] as? String }.flatMap { text in
            text.components(separatedBy: .newlines).compactMap { line -> String? in
                let prefix = "asset_id: "
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
            }
        }
        if addInventedID { ids.append("screenshot-999999") }
        let assignments = ids.map { ["asset_id": $0, "locale": "en-US", "confidence": 0.99] as [String: Any] }
        let json = try JSONSerialization.data(withJSONObject: ["assignments": assignments])
        return try textResponse(String(decoding: json, as: UTF8.self), responses: responses)
    }

    private static func textResponse(_ text: String, responses: Bool) throws -> Data {
        if responses {
            return try JSONSerialization.data(withJSONObject: [
                "status": "completed",
                "output": [
                    ["type": "reasoning", "summary": []],
                    [
                        "type": "message", "role": "assistant", "status": "completed",
                        "content": [["type": "output_text", "text": text, "annotations": []]],
                    ],
                ],
            ])
        }
        return try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": "stop", "message": ["content": text]]]
        ])
    }

    private static func failureResponse(_ failure: VisionResponseFailure) throws -> Data {
        switch failure {
        case .incomplete:
            return try JSONSerialization.data(withJSONObject: [
                "status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"],
                "output": [["type": "message", "content": [["type": "output_text", "text": "{\"assignments\":[]}"]]]],
            ])
        case .refusal:
            return try JSONSerialization.data(withJSONObject: [
                "status": "completed",
                "output": [["type": "message", "content": [["type": "refusal", "refusal": "Synthetic refusal"]]]],
            ])
        case .failed:
            return try JSONSerialization.data(withJSONObject: [
                "status": "failed", "error": ["message": "Synthetic failure"], "output": [],
            ])
        case .empty:
            return try JSONSerialization.data(withJSONObject: [
                "status": "completed", "output": [["type": "reasoning", "summary": []]],
            ])
        }
    }
}

enum VisionResponseFailure: CaseIterable, Sendable { case incomplete, refusal, failed, empty }

private struct VisionImageFixture {
    let folder: URL
    let assets: [ScreenshotAsset]
    init(count: Int) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vision-responses-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try #require(
            CGContext(
                data: nil, width: 1024, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let imageFolder = folder
        assets = try (1...count).map { index in
            let url = imageFolder.appendingPathComponent("shot-\(index).png")
            try (data as Data).write(to: url)
            return ScreenshotAsset(
                url: url, relativePath: "upload/shot-\(index).png", size: .init(width: 1024, height: 768),
                locale: nil, deviceSlot: .iPhone65, status: .ready, contentHash: "fixture-\(index)")
        }
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}

private final class VisionRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var values: [URLRequest] { lock.withLock { recorded } }
    func append(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
}

private final class VisionFixtureKeyStore: AIKeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: String] = [:]
    private var roles: [AIProfileRole] = []
    var readRoles: [AIProfileRole] { lock.withLock { roles } }
    init(text: String? = nil, vision: String? = nil) {
        for provider in [AIProvider.openai, .anthropic] {
            if let text { keys[provider.rawValue + AIProfileRole.text.rawValue] = text }
            if let vision { keys[provider.rawValue + AIProfileRole.vision.rawValue] = vision }
        }
    }
    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        lock.withLock { keys[provider.rawValue + role.rawValue] = apiKey }
    }
    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        lock.withLock {
            roles.append(role); return keys[provider.rawValue + role.rawValue]
        }
    }
    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        try load(for: provider, role: role)
    }
    func delete(for provider: AIProvider, role: AIProfileRole) throws {
        _ = lock.withLock { keys.removeValue(forKey: provider.rawValue + role.rawValue) }
    }
}

private struct VisionHTTPFixture {
    let host: String
    let session: URLSession
    var baseURL: URL { URL(string: "https://\(host)")! }
    init(recorder: VisionRequestRecorder, handler: @escaping @Sendable (URLRequest) throws -> Data) {
        host = "vision-\(UUID().uuidString.lowercased()).invalid"
        VisionResponsesURLProtocol.register(host: host) { request in
            recorder.append(request); return try handler(request)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VisionResponsesURLProtocol.self]
        session = URLSession(configuration: config)
    }
    func close() { session.invalidateAndCancel(); VisionResponsesURLProtocol.unregister(host: host) }
}

private final class VisionResponsesURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> Data] = [:]
    static func register(host: String, handler: @escaping @Sendable (URLRequest) throws -> Data) {
        lock.withLock { handlers[host] = handler }
    }
    static func unregister(host: String) { _ = lock.withLock { handlers.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let host = request.url?.host, let handler = Self.lock.withLock({ Self.handlers[host] }) else {
                throw URLError(.unsupportedURL)
            }
            // URLSession can replace large JSON bodies with a stream before
            // handing them to URLProtocol. Normalize the intercepted fixture
            // request so tests inspect the actual bytes in both cases.
            var capturedRequest = request
            if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
                capturedRequest.httpBodyStream = nil
                capturedRequest.httpBody = bytes
            }
            let data = try handler(capturedRequest)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
