import Foundation

enum AppleAdsReportRange: String, CaseIterable, Identifiable, Sendable {
    case days7
    case days30

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days7: L("Last 7 days")
        case .days30: L("Last 30 days")
        }
    }

    var dayCount: Int {
        switch self {
        case .days7: 7
        case .days30: 30
        }
    }
}

struct AppleAdsUser: Hashable, Sendable {
    var userId: String
    var orgId: String?
}

struct AppleAdsAccount: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var orgId: String?
    var currency: String
    var timeZone: String?
    var productFeatures: [String]
    var hasContentProviderDelegation: Bool

    var canRunAppStoreCampaigns: Bool {
        productFeatures.contains("APPSTORE_APP_MANUAL")
    }
}

struct AppleAdsACL: Hashable, Sendable {
    var roles: [String]
    var account: AppleAdsAccount
}

struct AppleAdsCampaign: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var status: String
    var adamId: String
    var dailyBudgetAmount: String?
    var dailyBudgetCurrency: String?
    var supplyPlacement: String?
    var displayStatus: String?

    var isEnabled: Bool {
        status.uppercased() == "ENABLED"
    }
}

struct AppleAdsCampaignMetrics: Hashable, Sendable {
    var campaignId: String
    var spend: Double
    var taps: Int
    var impressions: Int
    var installs: Int
    var currency: String

    var cpa: Double? {
        guard installs > 0 else { return nil }
        return spend / Double(installs)
    }
}

struct AppleAdsAdGroup: Identifiable, Hashable, Sendable {
    var id: String
    var campaignId: String
    var name: String
    var status: String
}

struct AppleAdsKeyword: Identifiable, Hashable, Sendable {
    var id: String
    var adGroupId: String
    var text: String
    var matchType: String
    var status: String
    var bidAmount: String?
}

struct AppleAdsSearchTerm: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var source: String?
    var taps: Int
    var installs: Int
    var spend: Double
}

struct AppleAdsKeywordSuggestion: Identifiable, Hashable, Sendable {
    var id: String { text }
    var text: String
    var source: String
}

struct AppleAdsKeywordDraft: Hashable, Sendable {
    var text: String
    var matchType: String
    var bidAmount: String?
}

struct AppleAdsEligibility: Hashable, Sendable {
    var adamId: String
    var isEligible: Bool
    var reasons: [String]
}

struct AppleAdsAppDetails: Hashable, Sendable {
    var adamId: String
    var name: String
    var availableStorefronts: [String]
    var currency: String?
}

struct AppleAdsPromoteRequest: Hashable, Sendable {
    static func validAmounts(budget: String, bid: String) -> Bool {
        let pattern = #"^[0-9]+(?:\.[0-9]{1,2})?$"#
        guard [budget, bid].allSatisfy({ $0.range(of: pattern, options: .regularExpression) != nil }) else { return false }
        guard let budget = Decimal(string: budget, locale: Locale(identifier: "en_US_POSIX")),
              let bid = Decimal(string: bid, locale: Locale(identifier: "en_US_POSIX")),
              budget > 0, bid > 0, bid <= budget else { return false }
        return true
    }

    var adamId: String
    var name: String
    var dailyBudget: String
    var currency: String
    var countries: [String]
    var defaultBid: String
    var keywords: [AppleAdsKeywordDraft]
}

enum AppleAdsDateFormat {
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Comma-separated App Store keywords plus notable What's New lines.
enum AppleAdsKeywordSeed {
    static func phrases(
        keywords: String,
        whatsNew: String,
        appName: String? = nil
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ raw: String) {
            let trimmed = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-*"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.count <= 80 else { return }
            let key = trimmed.lowercased()
            if let appName, key == appName.lowercased() { return }
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }

        for part in keywords.split(whereSeparator: { $0 == "," || $0 == "、" || $0 == ";" }) {
            append(String(part))
        }

        for line in whatsNew.split(whereSeparator: \.isNewline) {
            let cleaned = String(line)
                .replacingOccurrences(of: #"^[\s•\-\*]+"#, with: "", options: .regularExpression)
            if cleaned.count <= 40 {
                append(cleaned)
            } else {
                for word in cleaned.split(separator: " ") where word.count >= 4 {
                    append(String(word))
                }
            }
        }

        return Array(result.prefix(25))
    }
}
