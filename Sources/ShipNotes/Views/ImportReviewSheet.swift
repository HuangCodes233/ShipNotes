import SwiftUI

struct ImportReviewSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 560)
        .onAppear {
            if state.pendingImportSelectedLocale == nil {
                state.pendingImportSelectedLocale = locales.first
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L("Import Preview"), systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Spacer()
            Text(L("Review detected fields before importing."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let parsed = state.pendingImport {
            HStack(spacing: 0) {
                List(selection: Binding(
                    get: { state.pendingImportSelectedLocale },
                    set: { state.pendingImportSelectedLocale = $0 }
                )) {
                    ForEach(locales, id: \.self) { locale in
                        LocaleImportRow(locale: locale, candidates: parsed.candidatesByLocale[locale] ?? [])
                            .tag(Optional(locale))
                    }
                }
                .frame(minWidth: 180, idealWidth: 220)

                Divider()

                detail(parsed: parsed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(L("No import to review"), systemImage: "tray")
        }
    }

    private func detail(parsed: ParsedReleaseNotes) -> some View {
        let locale = state.pendingImportSelectedLocale ?? locales.first
        let candidates = locale.flatMap { parsed.candidatesByLocale[$0] } ?? []
        let selectedId = locale.flatMap { state.pendingImportSelections[$0] } ?? candidates.first?.id
        let candidate = selectedId.flatMap { id in candidates.first { $0.id == id } } ?? candidates.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(locale ?? "—")
                    .font(.callout.monospaced().weight(.semibold))
                Spacer()
                if let candidate {
                    Text(candidate.confidence.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            if let locale {
                Picker(L("Detected Field"), selection: Binding(
                    get: { state.pendingImportSelections[locale] ?? candidates.first?.id ?? "" },
                    set: { state.pendingImportSelections[locale] = $0 }
                )) {
                    ForEach(candidates) { candidate in
                        Text(candidate.title).tag(candidate.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 360, alignment: .leading)
            }

            if let candidate {
                HStack {
                    Text(L("%d characters", candidate.text.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ScrollView {
                    Text(candidate.text.isEmpty ? " " : candidate.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
            } else {
                ContentUnavailableView(L("Select a locale"), systemImage: "globe")
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button(L("Cancel")) {
                state.cancelPendingImport()
            }
            .keyboardShortcut(.cancelAction)

            if state.isAIConfigured {
                Button {
                    state.askAIToReparsePendingImport()
                } label: {
                    Label(L("Ask AI to re-parse"), systemImage: "sparkles")
                }
                .disabled(state.isAIRunning)
                .help(L("Ask the configured AI provider to re-extract release notes for each locale."))
            }

            if state.isAIRunning {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button {
                state.confirmPendingImport()
            } label: {
                Label(L("Import Selected Fields"), systemImage: "checkmark.circle")
            }
            .keyboardShortcut(.defaultAction)
            .primarySyncButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var locales: [String] {
        state.pendingImport?.candidatesByLocale.keys.sorted() ?? []
    }
}

private struct LocaleImportRow: View {
    let locale: String
    let candidates: [ReleaseNoteImportCandidate]

    var body: some View {
        HStack(spacing: 8) {
            Text(locale)
                .font(.callout.monospaced())
            Spacer()
            Text("\(candidates.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }
}
