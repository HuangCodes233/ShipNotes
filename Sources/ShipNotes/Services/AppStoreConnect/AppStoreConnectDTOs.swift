import Foundation

struct RemoteLocaleNote: Hashable, Sendable {
    var localizationId: String
    var locale: String
    var text: String
    var storeMetadata: StoreMetadataFields = .empty
}

struct ASCCollectionResponse<Resource: Decodable & Sendable>: Decodable, Sendable {
    let data: [Resource]
    let links: ASCPagedLinks?
}

/// Builds can include their prerelease-version resource. Apple stores the
/// marketing version on that related resource, not on the build itself.
struct ASCBuildCollectionResponse: Decodable, Sendable {
    let data: [ASCBuildResource]
    let included: [ASCPreReleaseVersionResource]?
    let links: ASCPagedLinks?
}

struct ASCResourceResponse<Resource: Decodable & Sendable>: Decodable, Sendable {
    let data: Resource
}

/// Same as `ASCResourceResponse` but allows the `data` field to be JSON null.
/// Use for to-one relationship endpoints like `GET /v1/appStoreVersions/{id}/build`
/// where Apple returns `{"data": null}` when nothing is attached.
struct ASCNullableResourceResponse<Resource: Decodable & Sendable>: Decodable, Sendable {
    let data: Resource?
}

struct ASCPagedLinks: Decodable, Sendable {
    let next: String?
}

struct ASCAppResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let name: String?
        let bundleId: String?
    }
}

struct ASCVersionResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let platform: String?
        let versionString: String?
        let appStoreState: String?
        let appVersionState: String?
        let createdDate: String?
    }
}

struct ASCLocalizationResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let locale: String?
        let description: String?
        let keywords: String?
        let marketingUrl: String?
        let promotionalText: String?
        let supportUrl: String?
        let whatsNew: String?
    }
}

struct ASCErrorResponse: Decodable, Sendable {
    let errors: [ASCErrorItem]
}

struct ASCErrorItem: Decodable, Sendable {
    let status: String?
    let code: String?
    let title: String?
    let detail: String?
    private let source: Source?

    private struct Source: Decodable, Sendable {
        let pointer: String?
    }

    // Example pointer: "/data/attributes/supportUrl" -> "supportUrl"
    private var attributeName: String? {
        guard let pointer = source?.pointer else { return nil }
        let segments = pointer.split(separator: "/").dropFirst(2)
        guard let name = segments.first, segments.count == 1 else { return nil }
        return String(name)
    }

    var displayMessage: String {
        var parts = [title, detail].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        if let attributeName {
            parts.append(attributeName)
        }
        if let code {
            parts.append(code)
        }
        return parts.joined(separator: " · ")
    }
}

struct ASCLocalizationUpdateRequest: Encodable, Sendable {
    let data: Resource

    init(id: String, whatsNew: String) {
        data = Resource(
            type: "appStoreVersionLocalizations",
            id: id,
            attributes: Attributes(whatsNew: whatsNew)
        )
    }

    init(id: String, metadata: StoreMetadataFields) {
        data = Resource(
            type: "appStoreVersionLocalizations",
            id: id,
            attributes: Attributes(metadata: metadata)
        )
    }

    init(id: String, field: StoreCopyField, value: String) {
        data = Resource(
            type: "appStoreVersionLocalizations",
            id: id,
            attributes: Attributes(field: field, value: value)
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Encodable, Sendable {
        let description: String?
        let keywords: String?
        let marketingUrl: String?
        let promotionalText: String?
        let supportUrl: String?
        let whatsNew: String?

        init(whatsNew: String) {
            self.description = nil
            self.keywords = nil
            self.marketingUrl = nil
            self.promotionalText = nil
            self.supportUrl = nil
            self.whatsNew = whatsNew
        }

        init(metadata: StoreMetadataFields) {
            self.description = metadata.description
            self.keywords = metadata.keywords
            self.marketingUrl = Self.urlAttributeValue(metadata.marketingURL)
            self.promotionalText = metadata.promotionalText
            self.supportUrl = Self.urlAttributeValue(metadata.supportURL)
            self.whatsNew = nil
        }

        init(field: StoreCopyField, value: String) {
            self.description = field == .description ? value : nil
            self.keywords = field == .keywords ? value : nil
            self.marketingUrl = field == .marketingURL ? Self.urlAttributeValue(value) : nil
            self.promotionalText = field == .promotionalText ? value : nil
            self.supportUrl = field == .supportURL ? Self.urlAttributeValue(value) : nil
            self.whatsNew = nil
        }

        // Apple rejects "" as an RFC 3986 URI with a 409, and untrimmed values
        // fail validation; an omitted key leaves the remote value untouched.
        static func urlAttributeValue(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct ASCLocalizationCreateRequest: Encodable, Sendable {
    let data: Resource

    init(versionId: String, locale: String, whatsNew: String) {
        data = Resource(
            type: "appStoreVersionLocalizations",
            attributes: Attributes(locale: locale, whatsNew: whatsNew),
            relationships: Relationships(
                appStoreVersion: Relationship(
                    data: RelationshipData(type: "appStoreVersions", id: versionId)
                )
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let locale: String
        let whatsNew: String
    }

    struct Relationships: Encodable, Sendable {
        let appStoreVersion: Relationship
    }

    struct Relationship: Encodable, Sendable {
        let data: RelationshipData
    }

    struct RelationshipData: Encodable, Sendable {
        let type: String
        let id: String
    }
}

// MARK: - Screenshots

struct ASCAppScreenshotSetResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?
    /// Present when the request includes `appScreenshots`; its order is the
    /// set's display order.
    let relationships: Relationships?

    struct Attributes: Decodable, Sendable {
        let screenshotDisplayType: String?
    }

    struct Relationships: Decodable, Sendable {
        let appScreenshots: ToManyRelationship?
    }

    struct ToManyRelationship: Decodable, Sendable {
        let data: [ResourceIdentifier]?
    }

    struct ResourceIdentifier: Decodable, Sendable {
        let id: String
    }
}

/// `GET …/appScreenshotSets?include=appScreenshots`: sets plus their
/// screenshots in one response.
struct ASCScreenshotSetsWithScreenshotsResponse: Decodable, Sendable {
    let data: [ASCAppScreenshotSetResource]
    let included: [ASCAppScreenshotResource]?
}

struct ASCAppScreenshotResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let fileName: String?
        let fileSize: Int?
        let imageAsset: ASCImageAsset?
        let assetDeliveryState: ASCAssetDeliveryState?
        let sourceFileChecksum: String?
        let uploadOperations: [ASCUploadOperation]?
    }
}

struct ASCAssetDeliveryState: Decodable, Sendable {
    let state: String?
    let errors: [Issue]?

    struct Issue: Decodable, Sendable {
        let code: String?
        let description: String?
    }
}

struct ASCImageAsset: Decodable, Sendable {
    let templateUrl: String?
    let width: Int?
    let height: Int?
}

struct ASCUploadOperation: Decodable, Sendable {
    let method: String?
    let url: URL?
    let offset: Int
    let length: Int
    let requestHeaders: [ASCUploadHeader]?
}

struct ASCUploadHeader: Decodable, Sendable {
    let name: String
    let value: String
}

struct ASCAppScreenshotSetCreateRequest: Encodable, Sendable {
    let data: Resource

    init(localizationId: String, displayType: String) {
        self.data = Resource(
            type: "appScreenshotSets",
            attributes: Attributes(screenshotDisplayType: displayType),
            relationships: Relationships(
                appStoreVersionLocalization: Relationship(
                    data: RelationshipData(type: "appStoreVersionLocalizations", id: localizationId)
                )
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let screenshotDisplayType: String
    }

    struct Relationships: Encodable, Sendable {
        let appStoreVersionLocalization: Relationship
    }

    struct Relationship: Encodable, Sendable {
        let data: RelationshipData
    }

    struct RelationshipData: Encodable, Sendable {
        let type: String
        let id: String
    }
}

struct ASCAppScreenshotCreateRequest: Encodable, Sendable {
    let data: Resource

    init(setId: String, fileName: String, fileSize: Int) {
        self.data = Resource(
            type: "appScreenshots",
            attributes: Attributes(fileName: fileName, fileSize: fileSize),
            relationships: Relationships(
                appScreenshotSet: Relationship(
                    data: RelationshipData(type: "appScreenshotSets", id: setId)
                )
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let fileName: String
        let fileSize: Int
    }

    struct Relationships: Encodable, Sendable {
        let appScreenshotSet: Relationship
    }

    struct Relationship: Encodable, Sendable {
        let data: RelationshipData
    }

    struct RelationshipData: Encodable, Sendable {
        let type: String
        let id: String
    }
}

struct ASCAppScreenshotUpdateRequest: Encodable, Sendable {
    let data: Resource

    init(id: String, uploaded: Bool, sourceFileChecksum: String) {
        self.data = Resource(
            type: "appScreenshots",
            id: id,
            attributes: Attributes(
                uploaded: uploaded,
                sourceFileChecksum: sourceFileChecksum
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Encodable, Sendable {
        let uploaded: Bool
        let sourceFileChecksum: String
    }
}

struct ASCAppScreenshotOrderRequest: Encodable, Sendable {
    let data: [RelationshipData]

    init(ids: [String]) {
        self.data = ids.map { RelationshipData(type: "appScreenshots", id: $0) }
    }

    struct RelationshipData: Encodable, Sendable {
        let type: String
        let id: String
    }
}

/// One build resource as returned by `GET /v1/builds`.
struct ASCBuildResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?

    struct Attributes: Decodable, Sendable {
        let version: String?           // CFBundleVersion
        let uploadedDate: Date?
        let expirationDate: Date?
        let processingState: String?
    }

    struct Relationships: Decodable, Sendable {
        let preReleaseVersion: ToOneRelationship?
    }

    struct ToOneRelationship: Decodable, Sendable {
        let data: ResourceIdentifier?
    }

    struct ResourceIdentifier: Decodable, Sendable {
        let id: String
    }
}

struct ASCPreReleaseVersionResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let version: String?
        let platform: String?
    }
}

/// `PATCH /v1/appStoreVersions/{id}/relationships/build` body. Set `buildId`
/// to attach a build, or pass nil to clear the relationship.
struct ASCBuildRelationshipUpdate: Encodable, Sendable {
    private let data: Payload?

    init(buildId: String?) {
        self.data = buildId.map { Payload(type: "builds", id: $0) }
    }

    struct Payload: Encodable, Sendable {
        let type: String
        let id: String
    }

    enum CodingKeys: CodingKey { case data }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let data {
            try container.encode(data, forKey: .data)
        } else {
            // Detach must serialize as `"data": null`, NOT omit the field.
            try container.encodeNil(forKey: .data)
        }
    }
}

// MARK: - Review submission

/// Resource returned by `POST /v1/reviewSubmissions` and friends.
struct ASCReviewSubmissionResource: Decodable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable, Sendable {
        let state: String?
        let submittedDate: Date?
        let platform: String?
    }
}

struct ASCReviewSubmissionItemResource: Decodable, Sendable {
    let id: String
    /// Present when the request includes `appStoreVersion`.
    let relationships: Relationships?

    struct Relationships: Decodable, Sendable {
        let appStoreVersion: ToOneRelationship?
    }

    struct ToOneRelationship: Decodable, Sendable {
        let data: ResourceIdentifier?
    }

    struct ResourceIdentifier: Decodable, Sendable {
        let id: String
    }
}

/// `POST /v1/reviewSubmissions` request body. Creates an open submission for
/// the given app. You then add reviewable items (e.g., the app version you want
/// reviewed) and finally PATCH `submitted: true`.
struct ASCReviewSubmissionCreateRequest: Encodable, Sendable {
    let data: Resource

    init(appId: String, platform: String) {
        self.data = Resource(
            type: "reviewSubmissions",
            attributes: Attributes(platform: platform),
            relationships: Relationships(app: Relationship(data: RelationshipData(type: "apps", id: appId)))
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }
    // `platform` is a REQUIRED attribute on reviewSubmissions — Apple rejects
    // the create without it. A submission is scoped to one platform.
    struct Attributes: Encodable, Sendable { let platform: String }
    struct Relationships: Encodable, Sendable { let app: Relationship }
    struct Relationship: Encodable, Sendable { let data: RelationshipData }
    struct RelationshipData: Encodable, Sendable { let type: String; let id: String }
}

/// `POST /v1/reviewSubmissionItems` body. Attaches a specific app store
/// version (the thing under review) to an open submission.
struct ASCReviewSubmissionItemCreateRequest: Encodable, Sendable {
    let data: Resource

    init(submissionId: String, versionId: String) {
        self.data = Resource(
            type: "reviewSubmissionItems",
            relationships: Relationships(
                reviewSubmission: Relationship(data: RelationshipData(type: "reviewSubmissions", id: submissionId)),
                appStoreVersion: Relationship(data: RelationshipData(type: "appStoreVersions", id: versionId))
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let relationships: Relationships
    }
    struct Relationships: Encodable, Sendable {
        let reviewSubmission: Relationship
        let appStoreVersion: Relationship
    }
    struct Relationship: Encodable, Sendable { let data: RelationshipData }
    struct RelationshipData: Encodable, Sendable { let type: String; let id: String }
}

/// `PATCH /v1/reviewSubmissions/{id}` body to actually submit (`submitted: true`).
struct ASCReviewSubmissionUpdateRequest: Encodable, Sendable {
    let data: Resource

    init(submissionId: String) {
        self.data = Resource(
            type: "reviewSubmissions",
            id: submissionId,
            attributes: Attributes(submitted: true)
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
    }
    struct Attributes: Encodable, Sendable { let submitted: Bool }
}

/// `PATCH /v1/appStoreVersions/{id}` body to update mutable attributes such
/// as `releaseType` (MANUAL / AFTER_APPROVAL / SCHEDULED).
struct ASCVersionUpdateRequest: Encodable, Sendable {
    let data: Resource

    init(versionId: String, releaseType: String? = nil, earliestReleaseDate: Date? = nil) {
        self.data = Resource(
            type: "appStoreVersions",
            id: versionId,
            attributes: Attributes(releaseType: releaseType, earliestReleaseDate: earliestReleaseDate)
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
    }
    struct Attributes: Encodable, Sendable {
        let releaseType: String?
        let earliestReleaseDate: Date?
    }
}

/// `POST /v1/appStoreVersions` request body. Creates a new editable version
/// for an app on a given platform.
struct ASCVersionCreateRequest: Encodable, Sendable {
    let data: Resource

    init(appId: String, versionString: String, platform: String) {
        self.data = Resource(
            type: "appStoreVersions",
            attributes: Attributes(platform: platform, versionString: versionString),
            relationships: Relationships(
                app: Relationship(
                    data: RelationshipData(type: "apps", id: appId)
                )
            )
        )
    }

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let platform: String
        let versionString: String
    }

    struct Relationships: Encodable, Sendable {
        let app: Relationship
    }

    struct Relationship: Encodable, Sendable {
        let data: RelationshipData
    }

    struct RelationshipData: Encodable, Sendable {
        let type: String
        let id: String
    }
}
