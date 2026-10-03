import Foundation

enum AIProfileRole: String, CaseIterable, Identifiable, Sendable {
    case text
    case vision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return L("Text AI")
        case .vision: return L("Vision AI")
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case none
    case anthropic
    case openai
    // case gemini      // future
    // case ollama      // future

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L("None")
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .none: return URL(string: "about:blank")!
        case .anthropic: return URL(string: "https://api.anthropic.com")!
        case .openai: return URL(string: "https://api.openai.com")!
        }
    }

    var defaultModel: String {
        switch self {
        case .none: return ""
        case .anthropic: return "claude-haiku-4-5"
        case .openai: return "gpt-4o-mini"
        }
    }

    func defaultModel(for role: AIProfileRole) -> String {
        switch (self, role) {
        case (.none, _):
            return ""
        case (.anthropic, .text):
            return "claude-haiku-4-5"
        case (.anthropic, .vision):
            return "claude-haiku-4-5"
        case (.openai, .text):
            return "gpt-4o-mini"
        case (.openai, .vision):
            return "gpt-4o-mini"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .none: return ""
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        }
    }

    var supportsVisionInput: Bool {
        switch self {
        case .anthropic, .openai: return true
        case .none: return false
        }
    }

    var keychainAccount: String { keychainAccount(for: .text) }
    var baseURLDefaultsKey: String { baseURLDefaultsKey(for: .text) }
    var modelDefaultsKey: String { modelDefaultsKey(for: .text) }

    func keychainAccount(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue)"
        case .vision: return "shipnotes.ai.vision.\(rawValue)"
        }
    }

    func baseURLDefaultsKey(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue).baseURL"
        case .vision: return "shipnotes.ai.vision.\(rawValue).baseURL"
        }
    }

    func modelDefaultsKey(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue).model"
        case .vision: return "shipnotes.ai.vision.\(rawValue).model"
        }
    }
}
