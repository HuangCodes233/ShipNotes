import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.stripMarkdownOnSync) private var stripMarkdown: Bool = false
    @AppStorage(LanguageManager.appStorageKey) private var uiLanguage: String = ""
    @AppStorage(AppearanceManager.appStorageKey) private var appearance: String = ""

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Language")).font(.headline)
                Picker(L("Language"), selection: $uiLanguage) {
                    ForEach(LanguageOption.allCases) { option in
                        Text(option.nativeName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: uiLanguage) { _, newValue in
                    let option = LanguageOption(rawValue: newValue) ?? .system
                    LanguageManager.setLanguage(option)
                    LanguageManager.promptRestart()
                }
                Text(L("Language change requires a restart."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Appearance")).font(.headline)
                Picker(L("Appearance"), selection: $appearance) {
                    ForEach(AppearanceOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: appearance) { _, newValue in
                    AppearanceManager.apply(AppearanceOption(rawValue: newValue) ?? .system)
                }
                Text(L("Takes effect immediately — no restart needed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Behavior")).font(.headline)
                Toggle(L("Strip markdown automatically before sync"), isOn: $stripMarkdown)
                Text(L("Headers, bold, links, and inline code are converted to plain text before a sync request."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

}
