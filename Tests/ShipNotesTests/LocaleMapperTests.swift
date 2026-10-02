import Testing
@testable import ShipNotes

@Suite("LocaleMapper")
struct LocaleMapperTests {
    let mapper = LocaleMapper()

    @Test func resolvesExactMatch() {
        #expect(mapper.resolve("en-US") == "en-US")
        #expect(mapper.resolve("zh-Hans") == "zh-Hans")
        #expect(mapper.resolve("ja") == "ja")
    }

    @Test func resolvesCommonAliases() {
        #expect(mapper.resolve("zh-CN") == "zh-Hans")
        #expect(mapper.resolve("zh-TW") == "zh-Hant")
        #expect(mapper.resolve("en") == "en-US")
        #expect(mapper.resolve("pt") == "pt-BR")
    }

    @Test func normalizesCasing() {
        #expect(mapper.resolve("EN-us") == "en-US")
        #expect(mapper.resolve("zh-hans") == "zh-Hans")
        #expect(mapper.resolve("ZH-CN") == "zh-Hans")
    }

    @Test func fallsBackToLangFamily() {
        #expect(mapper.resolve("en-IE") != nil)
        #expect(mapper.resolve("fr-BE") != nil)
    }

    @Test func returnsNilForUnknown() {
        #expect(mapper.resolve("xx-YY") == nil)
    }

    @Test func detectsLocaleFromFilename() {
        #expect(mapper.detectLocale(fromFilename: "en-US.md") == "en-US")
        #expect(mapper.detectLocale(fromFilename: "zh-Hans.markdown") == "zh-Hans")
        #expect(mapper.detectLocale(fromFilename: "ja.txt") == "ja")
    }

    @Test func localeTokensExtractsPathAndFilenameHints() {
        let tokens = LocaleMapper.localeTokens(from: "en-US")
        #expect(tokens.contains("en-US"))

        let underscored = LocaleMapper.localeTokens(from: "zh_Hans")
        #expect(underscored.contains("zh-Hans"))

        let spaced = LocaleMapper.localeTokens(from: "en US")
        #expect(spaced.contains("en-US") || spaced.contains("en"))
    }

    private func resolvedPathLocale(_ path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        return LocaleMapper.pathLocaleHints(components).lazy.compactMap { mapper.resolve($0) }.first
    }

    @Test func folderLocaleWinsOverWordsInTheFileName() {
        #expect(resolvedPathLocale("en-US/iPhone 6.5 no-ads 01.png") == "en-US")
        #expect(resolvedPathLocale("en-GB/try-it-now.png") == "en-GB")
        #expect(resolvedPathLocale("zh-Hant/6.9inch/zh-Hant_6.9inch_01.png") == "zh-Hant")
    }

    @Test func englishWordsThatLookLikeLanguageCodesAreIgnored() {
        #expect(resolvedPathLocale("screens/iPhone 6.5 no-ads 01.png") == nil)
        #expect(resolvedPathLocale("try-it-now.png") == nil)
        #expect(resolvedPathLocale("hi-res.png") == nil)
        #expect(resolvedPathLocale("no-ad-01.png") == nil)
        #expect(resolvedPathLocale("iphone-6.5/01-home.png") == nil)
    }

    @Test func realLocaleHintsInNamesStillResolve() {
        #expect(resolvedPathLocale("it/01.png") == "it")
        #expect(resolvedPathLocale("home_it-IT.png") == "it")
        #expect(resolvedPathLocale("home_de-DE.png") == "de-DE")
        #expect(resolvedPathLocale("zh-Hant_6.9inch_01.png") == "zh-Hant")
        #expect(resolvedPathLocale("zh_Hans/01.png") == "zh-Hans")
        #expect(resolvedPathLocale("01_ja.png") == "ja")
        #expect(resolvedPathLocale("en US/01.png") == "en-US")
        // Longer tags keep their region/script instead of the language default.
        #expect(resolvedPathLocale("en-GB-home.png") == "en-GB")
        #expect(resolvedPathLocale("fr-CA-screen.png") == "fr-CA")
        #expect(resolvedPathLocale("zh-Hant-TW/01.png") == "zh-Hant")
        #expect(resolvedPathLocale("en_GB_iPhone/01.png") == "en-GB")
    }

    @Test func screenshotSlotGroupsDependOnPlatformAndIPad() {
        #expect(ScreenshotSlotRequirement.groups(platform: "macOS", requiresIPad: true) == [.exact(.mac)])
        let iphone = ScreenshotSlotRequirement.groups(platform: "iOS", requiresIPad: false)
        #expect(iphone == [.oneOf([.iPhone69, .iPhone65])])
        let withIPad = ScreenshotSlotRequirement.groups(platform: "iOS", requiresIPad: true)
        #expect(withIPad.contains(.exact(.iPad13)))
    }
}
