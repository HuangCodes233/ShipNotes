import Foundation

enum StoreCopyField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case subtitle
    case description
    case keywords
    case promotionalText
    case supportURL
    case marketingURL
    case privacyPolicyURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtitle: L("Subtitle")
        case .description: L("Description")
        case .keywords: L("Keywords")
        case .promotionalText: L("Promotional Text")
        case .supportURL: L("Support URL")
        case .marketingURL: L("Marketing URL")
        case .privacyPolicyURL: L("Privacy Policy URL")
        }
    }

    var limit: Int? {
        switch self {
        case .subtitle: 30
        case .description: 4000
        case .keywords: 100
        case .promotionalText: 170
        case .supportURL, .marketingURL, .privacyPolicyURL: nil
        }
    }

    var isURLField: Bool {
        switch self {
        case .supportURL, .marketingURL, .privacyPolicyURL: true
        case .subtitle, .description, .keywords, .promotionalText: false
        }
    }

    var isVersionLocalizationField: Bool {
        switch self {
        case .description, .keywords, .promotionalText, .supportURL, .marketingURL: true
        // Subtitle and privacyPolicyURL live on the app-info level, not the version
        // localization — it can't be written through this endpoint.
        case .subtitle, .privacyPolicyURL: false
        }
    }
}

struct StoreMetadataFields: Hashable, Sendable, Codable {
    var subtitle: String
    var description: String
    var keywords: String
    var promotionalText: String
    var supportURL: String
    var marketingURL: String
    var privacyPolicyURL: String

    init(
        subtitle: String = "",
        description: String = "",
        keywords: String = "",
        promotionalText: String = "",
        supportURL: String = "",
        marketingURL: String = "",
        privacyPolicyURL: String = ""
    ) {
        self.subtitle = subtitle
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
        self.supportURL = supportURL
        self.marketingURL = marketingURL
        self.privacyPolicyURL = privacyPolicyURL
    }

    static let empty = StoreMetadataFields()

    var isEmpty: Bool {
        StoreCopyField.allCases.allSatisfy {
            value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func value(for field: StoreCopyField) -> String {
        switch field {
        case .subtitle: subtitle
        case .description: description
        case .keywords: keywords
        case .promotionalText: promotionalText
        case .supportURL: supportURL
        case .marketingURL: marketingURL
        case .privacyPolicyURL: privacyPolicyURL
        }
    }

    mutating func setValue(_ value: String, for field: StoreCopyField) {
        switch field {
        case .subtitle: subtitle = value
        case .description: description = value
        case .keywords: keywords = value
        case .promotionalText: promotionalText = value
        case .supportURL: supportURL = value
        case .marketingURL: marketingURL = value
        case .privacyPolicyURL: privacyPolicyURL = value
        }
    }
}

struct StoreCopyIssue: Hashable, Identifiable, Sendable {
    var id: Self { self }
    let field: StoreCopyField
    let severity: ValidationIssue.Severity
    let message: String
}

struct StoreCopyLocale: Identifiable, Hashable, Sendable {
    var id: String { locale }
    let locale: String
    var remoteLocalizationId: String?
    var localMetadata: StoreMetadataFields
    var remoteMetadata: StoreMetadataFields?
    var status: LocaleStatus
    var changedFieldCount: Int
    var validationIssues: [StoreCopyIssue] = []

    var issueCount: Int { validationIssues.count }
}
