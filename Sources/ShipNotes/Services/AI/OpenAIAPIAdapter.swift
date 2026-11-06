import Foundation

/// Adapts the app's existing structured chat prompts for either OpenAI wire
/// format. Text and screenshot services share this boundary; their domain
/// prompts and JSON parsers remain the same.
enum OpenAIAPIAdapter {
    static func requestBody(fromChatBody body: [String: Any], format: OpenAIAPIFormat) -> [String: Any] {
        guard format == .responses else { return body }
        var request = body
        if let messages = body["messages"] as? [[String: Any]] {
            request["input"] = messages.map { message in
                var input = message
                if let content = message["content"] as? [[String: Any]] {
                    input["content"] = content.map(inputContent)
                }
                return input
            }
        }
        if let responseFormat = body["response_format"] as? [String: Any] {
            var text = request["text"] as? [String: Any] ?? [:]
            if responseFormat["type"] as? String == "json_schema",
                var schema = responseFormat["json_schema"] as? [String: Any]
            {
                schema["type"] = "json_schema"
                text["format"] = schema
            } else {
                text["format"] = responseFormat
            }
            request["text"] = text
        }
        if let cap = body["max_completion_tokens"] ?? body["max_tokens"] {
            request["max_output_tokens"] = cap
        }
        for key in ["messages", "response_format", "max_tokens", "max_completion_tokens", "temperature"] {
            request.removeValue(forKey: key)
        }
        // This app sends release drafts/screenshots for one-shot work. Never
        // opt into retained Responses, even if an upstream chat body did.
        request["store"] = false
        return request
    }

    private static func inputContent(_ content: [String: Any]) -> [String: Any] {
        switch content["type"] as? String {
        case "text":
            var input = content
            input["type"] = "input_text"
            return input
        case "image_url":
            var input: [String: Any] = ["type": "input_image"]
            if let image = content["image_url"] as? [String: Any] {
                input["image_url"] = image["url"]
                input["detail"] = image["detail"]
            } else {
                input["image_url"] = content["image_url"]
            }
            return input
        default:
            return content
        }
    }

    static func text(from response: [String: Any], format: OpenAIAPIFormat) throws -> String {
        try AIRequestPolicy.validateOutputCompleteness(response)
        let text: String
        switch format {
        case .chatCompletions:
            guard let choices = response["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any]
            else {
                throw AIServiceError.invalidResponse("Response has no choices[0].message.content")
            }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                throw AIServiceError.requestRejected(refusal)
            }
            guard let content = message["content"] as? String else {
                throw AIServiceError.invalidResponse("Response has no choices[0].message.content")
            }
            text = content
        case .responses:
            try AIRequestPolicy.validateResponsesStatus(response)
            guard let output = response["output"] as? [[String: Any]] else {
                throw AIServiceError.invalidResponse("Responses output is missing")
            }
            var pieces: [String] = []
            for message in output where message["type"] as? String == "message" {
                if let status = message["status"] as? String, status != "completed" {
                    throw AIServiceError.invalidResponse("Responses message is \(status), not completed")
                }
                for content in message["content"] as? [[String: Any]] ?? [] {
                    if content["type"] as? String == "refusal" {
                        throw AIServiceError.requestRejected(
                            content["refusal"] as? String ?? "Model refused this request")
                    }
                    if content["type"] as? String == "output_text", let value = content["text"] as? String {
                        pieces.append(value)
                    }
                }
            }
            // Do not use the SDK's output_text convenience property, or accept
            // reasoning/tool-call strings as the requested user-facing result.
            text = pieces.joined()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.invalidResponse("OpenAI response has no text output")
        }
        return text
    }
}
