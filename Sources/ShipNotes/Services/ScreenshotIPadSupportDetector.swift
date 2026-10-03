import Foundation

enum ScreenshotIPadSupportOverride: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case required
    case ignored

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: L("Auto")
        case .required: L("Require iPad")
        case .ignored: L("Ignore iPad")
        }
    }
}

enum ScreenshotIPadSupportDetection: Hashable, Sendable {
    case supported(source: String)
    case unsupported(source: String)
    case unknown

    var supportsIPad: Bool? {
        switch self {
        case .supported: true
        case .unsupported: false
        case .unknown: nil
        }
    }

    var summary: String {
        switch self {
        case let .supported(source):
            L("Detected iPad support from %@.", source)
        case let .unsupported(source):
            L("Detected iPhone-only from %@.", source)
        case .unknown:
            L("Could not detect iPad support. iPad screenshots are ignored unless you choose Require iPad.")
        }
    }
}

enum ScreenshotIPadSupportDetector {
    static func detect(from inputURL: URL) -> ScreenshotIPadSupportDetection {
        let roots = candidateRoots(startingAt: inputURL)

        for root in roots {
            if let detection = detectExpoConfig(in: root) {
                return detection
            }
        }

        for root in roots {
            if let detection = detectInfoPlist(in: root) {
                return detection
            }
        }

        for root in roots {
            if let detection = detectXcodeProject(in: root) {
                return detection
            }
        }

        return .unknown
    }

    private static func candidateRoots(startingAt url: URL) -> [URL] {
        var current = normalizedDirectory(for: url)
        var roots: [URL] = []

        for _ in 0..<8 {
            roots.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return roots
    }

    private static func normalizedDirectory(for url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == false {
            return url.deletingLastPathComponent()
        }
        return url
    }

    private static func detectExpoConfig(in root: URL) -> ScreenshotIPadSupportDetection? {
        let configURL = root.appending(path: "app.json")
        guard FileManager.default.fileExists(atPath: configURL.path),
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let json = object as? [String: Any]
        else {
            return nil
        }

        let expo = json["expo"] as? [String: Any] ?? json
        guard let ios = expo["ios"] as? [String: Any],
            let supportsTablet = ios["supportsTablet"] as? Bool
        else {
            return nil
        }

        return supportsTablet
            ? .supported(source: "app.json ios.supportsTablet")
            : .unsupported(source: "app.json ios.supportsTablet")
    }

    private static func detectInfoPlist(in root: URL) -> ScreenshotIPadSupportDetection? {
        for plistURL in infoPlistCandidates(in: root) {
            guard let data = try? Data(contentsOf: plistURL),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let dictionary = plist as? [String: Any],
                let families = dictionary["UIDeviceFamily"] as? [Int],
                !families.isEmpty
            else {
                continue
            }

            return families.contains(2)
                ? .supported(source: "UIDeviceFamily")
                : .unsupported(source: "UIDeviceFamily")
        }
        return nil
    }

    private static func infoPlistCandidates(in root: URL) -> [URL] {
        var candidates = [root.appending(path: "Info.plist")]
        let iosRoot = root.appending(path: "ios")
        if let children = try? FileManager.default.contentsOfDirectory(
            at: iosRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates += children.map { $0.appending(path: "Info.plist") }
        }
        return candidates
    }

    private static func detectXcodeProject(in root: URL) -> ScreenshotIPadSupportDetection? {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        for projectURL in children where projectURL.pathExtension == "xcodeproj" {
            let pbxprojURL = projectURL.appending(path: "project.pbxproj")
            guard let text = try? String(contentsOf: pbxprojURL, encoding: .utf8),
                let detection = detectTargetedDeviceFamily(in: text)
            else {
                continue
            }
            return detection
        }
        return nil
    }

    private static func detectTargetedDeviceFamily(in text: String) -> ScreenshotIPadSupportDetection? {
        let appTargetValues = targetedDeviceFamilyValuesForApplicationTargets(in: text)
        if appTargetValues.foundApplicationTarget {
            return detection(from: appTargetValues.values, source: "main app TARGETED_DEVICE_FAMILY")
        }

        return detection(from: allTargetedDeviceFamilyValues(in: text), source: "TARGETED_DEVICE_FAMILY")
    }

    private static func detection(from values: [String], source: String) -> ScreenshotIPadSupportDetection? {
        let concreteValues = values.filter { value in
            value.range(of: #"\b[12]\b"#, options: .regularExpression) != nil
        }
        guard !concreteValues.isEmpty else { return nil }
        let supportsIPad = concreteValues.contains { value in
            value.range(of: #"\b2\b"#, options: .regularExpression) != nil
        }
        return supportsIPad
            ? .supported(source: source)
            : .unsupported(source: source)
    }

    private static let targetDeviceFamilyRegex = try! NSRegularExpression(
        pattern: #"TARGETED_DEVICE_FAMILY\s*=\s*([^;]+);"#)

    private static func allTargetedDeviceFamilyValues(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = targetDeviceFamilyRegex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return text[valueRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    private static func targetedDeviceFamilyValuesForApplicationTargets(
        in text: String
    ) -> (
        foundApplicationTarget: Bool,
        values: [String]
    ) {
        let nativeTargetBlocks = objectBlocks(
            in: text,
            isa: "PBXNativeTarget"
        )
        let appConfigurationListIDs = nativeTargetBlocks.compactMap { block -> String? in
            guard block.body.contains(#"productType = "com.apple.product-type.application";"#) else {
                return nil
            }
            return firstCapture(in: block.body, pattern: #"buildConfigurationList\s*=\s*([A-Za-z0-9]+)"#)
        }

        guard !appConfigurationListIDs.isEmpty else {
            return (false, [])
        }

        let configurationListBlocks = Dictionary(
            uniqueKeysWithValues: objectBlocks(in: text, isa: "XCConfigurationList").map { ($0.id, $0.body) }
        )
        let buildConfigurationBlocks = Dictionary(
            uniqueKeysWithValues: objectBlocks(in: text, isa: "XCBuildConfiguration").map { ($0.id, $0.body) }
        )

        let buildConfigurationIDs = appConfigurationListIDs.flatMap { listID -> [String] in
            guard let body = configurationListBlocks[listID],
                let listBody = firstCapture(in: body, pattern: #"buildConfigurations\s*=\s*\((.*?)\);"#)
            else {
                return []
            }
            return captures(in: listBody, pattern: #"([A-Za-z0-9]+)\s*/\*"#)
        }

        let values = buildConfigurationIDs.compactMap { configID -> String? in
            guard let body = buildConfigurationBlocks[configID] else { return nil }
            return firstCapture(in: body, pattern: #"TARGETED_DEVICE_FAMILY\s*=\s*([^;]+);"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return (true, values)
    }

    private static let objectBlocksRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z0-9]+)\s*/\*[^*]*\*/\s*=\s*\{(.*?)\n\s*\};"#, options: [.dotMatchesLineSeparators])

    private static func objectBlocks(in text: String, isa: String) -> [(id: String, body: String)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return objectBlocksRegex.matches(in: text, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: text),
                let bodyRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }
            let body = String(text[bodyRange])
            guard body.contains("isa = \(isa);") else { return nil }
            return (String(text[idRange]), body)
        }
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        captures(in: text, pattern: pattern).first
    }

    // Cache regexes for dynamic patterns used in captures
    nonisolated(unsafe) private static var capturesRegexCache: [String: NSRegularExpression] = [:]
    private static let capturesRegexCacheQueue = DispatchQueue(label: "com.shipnotes.capturesRegexCacheQueue")

    private static func captures(in text: String, pattern: String) -> [String] {
        let regex: NSRegularExpression? = capturesRegexCacheQueue.sync {
            if let cached = capturesRegexCache[pattern] { return cached }
            if let newRegex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                capturesRegexCache[pattern] = newRegex
                return newRegex
            }
            return nil
        }
        guard let regex = regex else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                let captureRange = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return String(text[captureRange])
        }
    }
}
