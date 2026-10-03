import Foundation

enum AIPrompts {
    static func storeMetadataParseSystemPrompt(formatInstructions: String) -> String {
        """
        You are a precise parser that extracts App Store product-page metadata \
        from project folders, README files, App Store metadata files, or draft copy.

        \(formatInstructions)

        ## Output rules
        - Use ONLY App Store Connect locale codes.
        - Return only locales you can extract with confidence. If no store-copy \
        fields can be extracted, return {"locales": {}}.
        - Do NOT invent product features, claims, prices, awards, ratings, \
        platform support, URLs, or privacy claims.
        - Prefer files under AppStore/metadata and fields named Subtitle, Description, \
        Keywords, Promotional Text, Support URL, Marketing URL, or Privacy Policy URL.
        - If the input is generic product text without explicit labels, you may \
        extract a description only; leave unknown fields empty.
        - Ignore release notes, changelogs, screenshot checklists, source code, \
        build logs, dependency files, and internal implementation notes.
        - Plain text only. No markdown headings, bold, tables, links-as-markdown, \
        or emoji in returned fields.
        - subtitle must be <= 30 characters, description must be <= 4000 characters, \
        keywords <= 100 characters, promotionalText <= 170 characters.
        """
    }

    static func storeMetadataParseUserPrompt(
        text: String,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?
    ) -> String {
        var prompt = """
            App name: \(appName)
            Version: \(versionString ?? "(not specified)")
            Default locale if the text has no locale marker: \(defaultLocale ?? "(none)")
            """
        if !knownRemoteLocales.isEmpty {
            prompt +=
                "\nKnown App Store Connect locales for this app: \(knownRemoteLocales.sorted().joined(separator: ", "))"
        }
        prompt += "\n\n--- BEGIN LOCAL FILES ---\n"
        prompt += text
        prompt += "\n--- END LOCAL FILES ---\n"
        return prompt
    }

    static func parseSystemPrompt(formatInstructions: String) -> String {
        """
        You are a precise parser that extracts App Store release-notes bodies \
        from arbitrarily-formatted text files.

        \(formatInstructions)

        ## Output rules
        - Use ONLY these App Store Connect locale codes:
          ar-SA, ca, cs, da, de-DE, el, en-AU, en-CA, en-GB, en-US, es-ES, es-MX, fi, \
        fr-CA, fr-FR, he, hi, hr, hu, id, it, ja, ko, ms, nl-NL, no, pl, pt-BR, pt-PT, \
        ro, ru, sk, sv, th, tr, uk, vi, zh-Hans, zh-Hant.
        - Do NOT invent content. If you cannot extract a body for a locale with \
        high confidence, omit that locale entirely.
        - The input may be a project-folder dump with `=== FILE: path ===` \
        headers. Prefer files under AppStore/metadata, files named like \
        release-notes, whats-new, or changelog, and ignore source code, design \
        notes, screenshot captions, descriptions, keywords, and marketing copy.

        ## Content rules
        - The body should contain only the user-facing release notes (bullet lists, \
        short paragraphs). Strip:
          - section headings ("App Name", "Description", "What's New", numbered \
        headings like "## 9. What's New")
          - character-limit annotations like "(27 chars)" / "**Limit: 30 characters**"
          - file-level banners, comments starting with `#` (when they're meta, not \
        bullets), table-of-contents headers, version markers like \
        "Was ist neu in v2.12.3:" / "v1.7 — Visual Refresh"
          - flag emojis, language-name H3 headings, separator dashes (---), \
        section dividers like "==========".
        - PRESERVE bullet markers (•, -, *) and line breaks within the body.
        - DO NOT include any markdown formatting (no **bold**, no [links](url), \
        no `code`, no `### headings`). App Store renders release notes as plain text.

        ## Version filter
        - If the user provides currentVersion, return ONLY the body matching that \
        version for each locale. Multi-version files contain several version \
        sections; pick the one matching currentVersion (or its prefix, e.g., \
        "1.7" matches "v1.7.0").
        - If currentVersion is not provided OR no exact match exists, return the \
        latest (first) version in the file.

        ## Locale identification
        Match these signals (in priority order) to figure out which locale each \
        section belongs to:
        1. Flag emojis: 🇺🇸→en-US, 🇬🇧→en-GB, 🇦🇺→en-AU, 🇨🇦→en-CA, 🇨🇳→zh-Hans, \
        🇹🇼→zh-Hant, 🇯🇵→ja, 🇰🇷→ko, 🇪🇸→es-ES, 🇲🇽→es-MX, 🇫🇷→fr-FR, 🇩🇪→de-DE, \
        🇧🇷→pt-BR, 🇵🇹→pt-PT, etc.
        2. Region hints in parens: "English（美国/USA）"→en-US, "English（英国/UK）"→en-GB, \
        "English（澳大利亚/Australia）"→en-AU, "English（加拿大/Canada）"→en-CA, \
        "Español（西班牙/Spain）"→es-ES, "Español（墨西哥/Mexico）"→es-MX.
        3. Locale codes embedded in headings ("zh-Hans", "en-US", "ja").
        4. Native or English language names ("简体中文"→zh-Hans, "繁體中文"→zh-Hant, \
        "日本語"→ja, "한국어"→ko, "English"→en-US default, "Español"→es-ES default, \
        "Français"→fr-FR default, "Tiếng Việt"→vi, etc.).
        5. As a last resort, infer from the script/characters in the body content.
        """
    }

    static func parseUserPrompt(
        text: String,
        currentVersion: String?,
        knownRemoteLocales: [String]
    ) -> String {
        var prompt = ""
        if let v = currentVersion {
            prompt += "currentVersion: \(v)\n"
        } else {
            prompt += "currentVersion: (none — pick the latest version section)\n"
        }
        if !knownRemoteLocales.isEmpty {
            prompt +=
                "App Store Connect already has these locales enabled for this app, so prefer extracting them when present: \(knownRemoteLocales.sorted().joined(separator: ", "))\n"
        }
        prompt += "\n--- BEGIN RELEASE NOTES FILE ---\n"
        prompt += text
        prompt += "\n--- END RELEASE NOTES FILE ---\n"
        return prompt
    }

    static func translateSystemPrompt(formatInstructions: String) -> String {
        """
        You are a translator producing App Store Connect release notes.

        \(formatInstructions)

        ## Content rules
        - Preserve bullet markers (•, -, *) and line breaks exactly.
        - Use plain text only — App Store renders release notes as plain text.
        - Keep proper nouns, app names, feature names, and any glossary terms \
        verbatim (do not translate them).
        - Match the tone of the source (friendly, concise, user-facing).
        - Match the natural conventions of the target locale (punctuation, \
        date format, quotation marks).
        - Do not add or remove bullet points compared to the source.
        """
    }

    static func translateUserPrompt(
        text: String,
        fromLocale: String,
        toLocale: String,
        glossary: [String: String]
    ) -> String {
        var prompt = "Source locale: \(fromLocale)\n"
        prompt += "Target locale: \(toLocale)\n"
        if !glossary.isEmpty {
            prompt += "Glossary (keep verbatim):\n"
            for (term, translation) in glossary.sorted(by: { $0.key < $1.key }) {
                prompt += "  \(term): \(translation)\n"
            }
        }
        prompt += "\n--- BEGIN SOURCE ---\n"
        prompt += text
        prompt += "\n--- END SOURCE ---\n"
        return prompt
    }

    static func storeMetadataSystemPrompt(formatInstructions: String) -> String {
        """
        You are an App Store product-page copy editor.

        \(formatInstructions)

        ## Content rules
        - Optimize only the text the user already provided. Do not invent features, awards, ratings, prices, guarantees, or platform support.
        - Use the target locale naturally and keep the tone clear, useful, and App Store friendly.
        - Plain text only. No markdown headings, bold, links, tables, or emoji.
        - subtitle must be 30 characters or fewer.
        - description must be 4000 characters or fewer.
        - keywords must be a comma-separated App Store keyword string, 100 characters or fewer, with no hashtags.
        - promotionalText must be 170 characters or fewer.
        - Preserve supportURL, marketingURL, and privacyPolicyURL exactly as supplied. If any URL is empty, return an empty string for it.
        """
    }

    static func storeMetadataUserPrompt(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) -> String {
        """
        App name: \(appName)
        Locale: \(locale)
        Version: \(versionString ?? "(not specified)")

        Current subtitle:
        \(metadata.subtitle)

        Current description:
        \(metadata.description)

        Current keywords:
        \(metadata.keywords)

        Current promotionalText:
        \(metadata.promotionalText)

        Current supportURL:
        \(metadata.supportURL)

        Current marketingURL:
        \(metadata.marketingURL)

        Current privacyPolicyURL:
        \(metadata.privacyPolicyURL)
        """
    }
}
