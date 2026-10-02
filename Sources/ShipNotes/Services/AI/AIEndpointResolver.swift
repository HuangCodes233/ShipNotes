import Foundation

enum AIEndpointResolver {
    static func openAIChatCompletions(from baseURL: URL) -> URL {
        endpoint(
            from: baseURL,
            defaultPath: ["v1", "chat", "completions"],
            acceptedTerminalPaths: [
                ["v1", "chat", "completions"],
                ["chat", "completions"]
            ]
        )
    }

    static func anthropicMessages(from baseURL: URL) -> URL {
        endpoint(
            from: baseURL,
            defaultPath: ["v1", "messages"],
            acceptedTerminalPaths: [
                ["v1", "messages"],
                ["messages"]
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
            return baseURL
        }

        var url = baseURL
        let pathToAppend = existingPath.last == defaultPath.first
            ? defaultPath.dropFirst()
            : defaultPath[...]
        for component in pathToAppend {
            url.append(path: component)
        }
        return url
    }
}
