import Foundation

enum AIEndpointResolver {
    static func openAIChatCompletions(from baseURL: URL) -> URL {
        openAI(from: baseURL, format: .chatCompletions)
    }

    static func openAI(from baseURL: URL, format: OpenAIAPIFormat) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        // Work with encoded components: reconstructing URL.path would turn a
        // proxy's encoded tenant separator (%2F) into a different route.
        let existingPath = components.percentEncodedPath.split(separator: "/").map(String.init)
        let target = format == .responses ? ["responses"] : ["chat", "completions"]
        let path: [String]
        if existingPath.suffix(2) == ["chat", "completions"] {
            path = Array(existingPath.dropLast(2)) + target
        } else if existingPath.last == "responses" {
            path = Array(existingPath.dropLast()) + target
        } else if existingPath.last == "v1" {
            path = existingPath + target
        } else if existingPath.isEmpty, format == .responses, baseURL.host?.lowercased() == "api.deepseek.com" {
            path = target
        } else {
            // Preserve the existing /v1 convention for official OpenAI roots
            // and arbitrary proxy prefixes; explicit endpoints stay exact.
            path = existingPath + ["v1"] + target
        }
        components.percentEncodedPath = "/" + path.joined(separator: "/")
        return components.url ?? baseURL
    }

    static func anthropicMessages(from baseURL: URL) -> URL {
        endpoint(
            from: baseURL,
            defaultPath: ["v1", "messages"],
            acceptedTerminalPaths: [
                ["v1", "messages"],
                ["messages"],
            ]
        )
    }

    private static func endpoint(
        from baseURL: URL,
        defaultPath: [String],
        acceptedTerminalPaths: [[String]]
    ) -> URL {
        let existingPath = baseURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        for terminalPath in acceptedTerminalPaths where existingPath.suffix(terminalPath.count) == terminalPath[...] {
            // Rebuild without a trailing slash: `…/v1/messages/` (kept verbatim
            // before) 404s on strict proxies.
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = "/" + existingPath.joined(separator: "/")
            return components?.url ?? baseURL
        }

        var url = baseURL
        let pathToAppend =
            existingPath.last == defaultPath.first
            ? defaultPath.dropFirst()
            : defaultPath[...]
        for component in pathToAppend {
            url.append(path: component)
        }
        return url
    }
}
