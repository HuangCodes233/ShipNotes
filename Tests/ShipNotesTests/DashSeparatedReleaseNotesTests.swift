import Testing
import Foundation
@testable import ShipNotes

/// Tests the dash-separated release-notes format. One file = one version,
/// sections like `--- 日本語（主要）---`, `--- English（美国）---`,
/// `--- English（英国）---` with plain-text bodies (no ``` fences).
@Suite("DashSeparatedReleaseNotes")
struct DashSeparatedReleaseNotesTests {
    private let parser = ReleaseNotesParser()

    @Test func crlfLineEndingsDoNotProduceBlankLines() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        // Windows-saved file: CRLF everywhere.
        let crlf = sampleFile.replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(parsed.locales["ja"]?.contains("ひと目でわかる") == true)
        // The body must not contain doubled blank lines from the CRLF split.
        let body = parsed.locales["ja"] ?? ""
        #expect(!body.contains("\n\n\n"))
    }

    @Test func utf8BomDoesNotBreakFirstSection() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        var bom = "\u{FEFF}"
        bom.append(sampleFile)
        try bom.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(parsed.locales["ja"]?.contains("ひと目でわかる") == true)
    }

    @Test func extractsAllLanguageSectionsByName() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)

        #expect(parsed.locales["ja"]?.contains("ひと目でわかる") == true)
        #expect(parsed.locales["fr-FR"]?.contains("Vous cherchez") == true)
        #expect(parsed.locales["zh-Hant"]?.contains("一眼就看見") == true)
        #expect(parsed.locales["ko"]?.contains("자꾸 찾아보는") == true)
        #expect(parsed.locales["zh-Hans"]?.contains("一眼就看到") == true)
        #expect(parsed.locales["es-ES"]?.contains("Las palabras") == true)
        #expect(parsed.locales["vi"]?.contains("Những từ") == true)
    }

    @Test func splitsEnglishVariantsByRegionInParens() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)

        // All four English variants should land in their own locale slot.
        #expect(parsed.locales["en-US"] != nil, "Expected en-US from English（美国）")
        #expect(parsed.locales["en-GB"] != nil, "Expected en-GB from English（英国）")
        #expect(parsed.locales["en-AU"] != nil, "Expected en-AU from English（澳大利亚）")
        #expect(parsed.locales["en-CA"] != nil, "Expected en-CA from English（加拿大）")

        // The bodies happen to be identical in this sample — that's fine.
        let bodies = [parsed.locales["en-US"], parsed.locales["en-GB"],
                      parsed.locales["en-AU"], parsed.locales["en-CA"]]
        for body in bodies {
            #expect(body?.contains("Frequent words") == true)
        }
    }

    @Test func splitsSpanishByRegionWhenSpain() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(parsed.locales["es-ES"]?.contains("Las palabras") == true)
        // Should NOT incorrectly produce es-MX since the file only has 西班牙.
        #expect(parsed.locales["es-MX"] == nil)
    }

    @Test func filterIntroAndCommentsBeforeFirstSection() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        for (locale, body) in parsed.locales {
            #expect(!body.contains("Ordered to match"),
                    "locale \(locale) leaked pre-section file-level comment")
            #expect(!body.contains("Feature release:"),
                    "locale \(locale) leaked pre-section file-level comment")
            #expect(!body.contains("=========="),
                    "locale \(locale) leaked the file header banner")
        }
    }

    @Test func inferVersionFromFileBody() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(parsed.version == "3.0.0")
    }

    @Test func appliesDirectlyWithoutPreviewSheet() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ReleaseNotes_v3.0.0.txt")
        try sampleFile.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(!parsed.requiresReview)
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesDashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private let sampleFile = """
    ========== v3.0.0 Release Notes ==========
    # Ordered to match App Store Connect's "已本地化" list (2026).
    # Feature release: word query statistics — words you look up again and again
    # get their own ranking, with a gentle nudge to memorise them.

    --- 日本語（主要）---
    v3.0.0  — 調べた単語が、ひと目でわかるように
    - 同じ漢字を何度も調べていませんか？読みを3回以上調べた単語が「よく調べた単語」として自動でまとまります
    - 設定に「学習統計」を追加。これまでに調べた語数と、まだ覚えられていない単語の一覧をいつでも確認できます
    - 単語の詳細画面で「この単語は3回調べています」とそっとお知らせ。その場でワンタップでお気に入りに登録できます
    - 統計はすべて端末内で完結し、iCloudをオンにすればお使いの端末間で同期されます

    --- Français ---
    v3.0.0 — Les mots que vous cherchez sans cesse, mis en lumière
    - Vous cherchez toujours le même kanji ? Les mots dont vous consultez la lecture 3 fois ou plus sont automatiquement regroupés dans « Mots fréquents »
    - Nouvelle section « Statistiques d'apprentissage » dans les Réglages : retrouvez à tout moment le nombre de mots consultés et la liste de ceux qui résistent encore
    - Dans le détail d'un mot, un petit rappel « Vous avez cherché ce mot 3 fois » apparaît, avec un ajout aux favoris en un seul tap
    - Toutes les statistiques restent sur votre appareil et se synchronisent entre vos appareils si iCloud est activé

    --- 繁體中文 ---
    v3.0.0 你常常查的詞，一眼就看見
    - 同一個漢字總是記不住讀音？查過 3 次以上的詞會自動歸入「常查單詞」
    - 設定新增「學習統計」：隨時查看一共查過多少詞，以及那些還沒記牢的單詞數量
    - 單詞詳情頁會貼心提醒「這個詞你已經查過 3 次」，可一鍵加入收藏
    - 統計資料全部存在裝置本機，開啟 iCloud 後可在你的多台裝置間同步

    --- 한국어 ---
    v3.0.0 — 자꾸 찾아보는 단어가 한눈에
    - 같은 한자의 읽기를 자꾸 잊으시나요? 3회 이상 찾아본 단어가 '자주 찾는 단어'로 자동 정리됩니다
    - 설정에 '학습 통계'를 추가했습니다. 지금까지 찾아본 단어 수와 아직 외우지 못한 단어 목록을 언제든 확인하세요
    - 단어 상세 화면에서 '이 단어를 3번 찾아봤어요'라고 살짝 알려 주고, 그 자리에서 한 번에 즐겨찾기에 담을 수 있습니다
    - 모든 통계는 기기 안에서만 처리되며, iCloud를 켜면 사용 중인 기기 간에 동기화됩니다

    --- 简体中文 ---
    v3.0.0 你反复查的词，一眼就看到
    - 同一个汉字总是记不住读音？查过 3 次以上的词会自动归入「常查单词」
    - 设置新增「学习统计」，随时查看一共查过多少词，以及那些还没记牢的单词数量
    - 单词详情页会贴心提醒「这个词你已经查过 3 次」，可一键加入收藏
    - 统计数据全部保存在设备本机，开启 iCloud 后可在你的多台设备间同步

    --- Español（西班牙）---
    v3.0.0 — Las palabras que buscas una y otra vez, a la vista
    - ¿Siempre se te escapa la lectura del mismo kanji? Las palabras que consultas 3 veces o más se agrupan solas en «Palabras frecuentes»
    - Nueva sección «Estadísticas de aprendizaje» en Ajustes: consulta cuántas palabras has buscado y la lista de las que aún no se te quedan
    - En el detalle de una palabra aparece un aviso amable «Has buscado esta palabra 3 veces», con un toque para añadirla a favoritos
    - Todas las estadísticas se quedan en tu dispositivo y se sincronizan entre tus dispositivos si activas iCloud

    --- English（美国）---
    v3.0.0 — The words you keep looking up, at a glance
    - Always forgetting the same kanji? Words you look up 3 or more times are grouped on their own as "Frequent words"
    - New "Learning Stats" section in Settings: see how many words you've looked up, plus the list of the ones that haven't stuck yet
    - The word detail screen gently reminds you "You've looked this word up 3 times," with a one-tap add to favourites
    - All stats stay on your device, and sync across your devices when iCloud is on

    --- English（英国）---
    v3.0.0 — The words you keep looking up, at a glance
    - Always forgetting the same kanji? Words you look up 3 or more times are grouped on their own as "Frequent words"
    - New "Learning Stats" section in Settings: see how many words you've looked up, plus the list of the ones that haven't stuck yet
    - The word detail screen gently reminds you "You've looked this word up 3 times," with a one-tap add to favourites
    - All stats stay on your device, and sync across your devices when iCloud is on

    --- English（澳大利亚）---
    v3.0.0 — The words you keep looking up, at a glance
    - Always forgetting the same kanji? Words you look up 3 or more times are grouped on their own as "Frequent words"
    - New "Learning Stats" section in Settings: see how many words you've looked up, plus the list of the ones that haven't stuck yet
    - The word detail screen gently reminds you "You've looked this word up 3 times," with a one-tap add to favourites
    - All stats stay on your device, and sync across your devices when iCloud is on

    --- English（加拿大）---
    v3.0.0 — The words you keep looking up, at a glance
    - Always forgetting the same kanji? Words you look up 3 or more times are grouped on their own as "Frequent words"
    - New "Learning Stats" section in Settings: see how many words you've looked up, plus the list of the ones that haven't stuck yet
    - The word detail screen gently reminds you "You've looked this word up 3 times," with a one-tap add to favourites
    - All stats stay on your device, and sync across your devices when iCloud is on

    --- Tiếng Việt ---
    v3.0.0 Những từ bạn tra đi tra lại, hiện rõ trong tầm mắt
    - Cứ quên hoài cách đọc của cùng một chữ Hán? Những từ bạn tra từ 3 lần trở lên sẽ tự gom thành «Từ tra nhiều»
    - Thêm mục «Thống kê học tập» trong Cài đặt: xem bạn đã tra bao nhiêu từ và danh sách những từ vẫn chưa thuộc
    - Màn hình chi tiết từ nhẹ nhàng nhắc «Bạn đã tra từ này 3 lần», kèm nút thêm vào yêu thích chỉ với một chạm
    - Mọi thống kê đều nằm trong máy của bạn, và đồng bộ giữa các thiết bị khi bật iCloud
    """
}
