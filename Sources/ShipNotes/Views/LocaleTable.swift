import SwiftUI

struct LocaleTable: View {
    @Environment(AppState.self) private var state

    @State private var sortOrder = [KeyPathComparator(\LocaleNote.status)]

    var body: some View {
        @Bindable var state = state

        Table(
            state.localeNotes.sorted(using: sortOrder),
            selection: Binding<String?>(
                get: { state.selectedLocale },
                set: { if let code = $0 { state.selectLocale(code) } }
            ), sortOrder: $sortOrder
        ) {
            TableColumn(L("Locale"), value: \.locale) { note in
                HStack(spacing: 6) {
                    Text(note.locale).font(.callout.monospaced())
                    if note.localPath != nil {
                        Image(systemName: "doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn(L("Status"), value: \.status) { note in
                StatusBadge(status: note.status)
            }
            .width(min: 110, ideal: 140)

            TableColumn(L("Length"), value: \.length) { note in
                Text("\(note.length)")
                    .foregroundStyle(note.length > ValidationEngine.whatsNewCharacterLimit ? .red : .secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn(L("Diff")) { note in
                if let summary = note.diffSummary, summary.hasChanges {
                    HStack(spacing: 6) {
                        Text("+\(summary.added)").foregroundStyle(.green).monospacedDigit()
                        Text("-\(summary.removed)").foregroundStyle(.red).monospacedDigit()
                    }
                    .font(.caption)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 70, ideal: 90)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(minHeight: 200)
        .contextMenu(forSelectionType: String.self) { selectedLocales in
            if let code = selectedLocales.first {
                Button {
                    state.copyLocalText(code)
                } label: {
                    Label(L("Copy Markdown"), systemImage: "doc.on.doc")
                }
                Button {
                    state.revertToRemote(code)
                } label: {
                    Label(L("Revert to Remote"), systemImage: "arrow.uturn.backward")
                }
                .disabled(state.localeNotes.first { $0.locale == code }?.remoteText == nil)

                Divider()

                Button {
                    state.syncLocale(code)
                } label: {
                    Label(L("Sync This Locale Only"), systemImage: "icloud.and.arrow.up")
                }
                .disabled(
                    state.isLoadingRemote || state.isSyncing || !(state.selectedVersion?.canEditMetadata ?? false))

                Divider()

                if state.isAIConfigured {
                    let nonEmptySources = state.localeNotes.filter {
                        $0.locale != code && !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    Menu {
                        ForEach(nonEmptySources) { source in
                            Button(source.locale) {
                                state.translateLocale(code, fromLocale: source.locale)
                            }
                        }
                    } label: {
                        Label(L("AI Translate from…"), systemImage: "wand.and.stars")
                    }
                    .disabled(state.isAIRunning || nonEmptySources.isEmpty)

                    let hasEmptyTargets = state.localeNotes.contains {
                        $0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    Menu {
                        ForEach(
                            state.localeNotes.filter {
                                !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                        ) { source in
                            Button(L("From %@", source.locale)) {
                                state.translateAllEmptyLocales(from: source.locale)
                            }
                        }
                    } label: {
                        Label(L("AI Translate All Empty Locales from…"), systemImage: "wand.and.stars.inverse")
                    }
                    .disabled(state.isAIRunning || !hasEmptyTargets)
                } else {
                    Button {
                    } label: {
                        Label(L("AI Translate (configure in Settings)"), systemImage: "wand.and.stars")
                    }
                    .disabled(true)
                }
            }
        }
    }
}
