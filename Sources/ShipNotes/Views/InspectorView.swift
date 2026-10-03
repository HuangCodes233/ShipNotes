import SwiftUI

struct InspectorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 14) {
            languageHeader
            if let note = state.selectedLocaleNote {
                DiffView(note: note)
                Divider()
                EditorView(note: note)
            } else {
                ContentUnavailableView {
                    Label(L("Select a locale"), systemImage: "globe")
                } description: {
                    Text(L("Choose a locale in the table to preview and edit its release notes."))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        // No descendant-propagating .animation(...) here — it makes the
        // sidebar column toggle feel laggy because every frame of the
        // NavigationSplitView animation traverses this modifier.
    }

    private var languageHeader: some View {
        @Bindable var state = state
        return HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.tint)
            Picker(
                L("Locale"),
                selection: Binding(
                    get: { state.selectedLocale ?? "" },
                    set: { if !$0.isEmpty { state.selectLocale($0) } }
                )
            ) {
                ForEach(state.localeNotes) { note in
                    Text(localeDisplayName(note.locale)).tag(note.locale)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 200)
            Spacer()
            if let note = state.selectedLocaleNote {
                StatusBadge(status: note.status)
            }
        }
    }

    /// Show "简体中文 (zh-Hans)" instead of a bare code; falls back to the raw
    /// code when the system has no display name for it.
    private func localeDisplayName(_ code: String) -> String {
        guard let name = Locale(identifier: code).localizedString(forIdentifier: code), !name.isEmpty else {
            return code
        }
        return "\(name) (\(code))"
    }

}
