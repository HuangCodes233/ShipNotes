import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var state
    let note: LocaleNote

    private var textBinding: Binding<String> {
        Binding(
            get: { note.localText },
            set: { state.updateLocalText(for: note.locale, text: $0) }
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Release Notes")).font(.headline)
                Spacer()

                // Quick Markdown Formatting Actions
                HStack(spacing: 6) {
                    Button {
                        state.updateLocalText(for: note.locale, text: bulletized(note.localText))
                    } label: {
                        Label(L("Add Bullet List"), systemImage: "list.bullet")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Add Bullet List"))

                    Button {
                        let cleaned = ValidationEngine().stripMarkdownToPlainText(note.localText)
                        state.updateLocalText(for: note.locale, text: cleaned)
                    } label: {
                        Label(L("Clean Formatting"), systemImage: "sparkles")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Strip Markdown formatting for App Store compliance"))
                }
                .padding(.trailing, 8)
                // Validation issues render once, in `issuesList` below the
                // editor, with full messages and the Auto Fix action — a second
                // icon-only copy here just duplicated them.
            }

            TextEditor(text: textBinding)
                .accessibilityLabel(L("Release Notes"))
                .font(.system(.body, design: .default))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                // Leave room at the bottom for the character ring so the last
                // line of text isn't hidden behind it (prevents a phantom
                // scrollbar when the text otherwise fits).
                .contentMargins(.bottom, 28, for: .scrollContent)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .overlay(alignment: .bottomTrailing) {
                    // Always mounted: CharacterRing renders the red "+N over"
                    // badge itself when the limit is exceeded, so the counter
                    // never vanishes at the exact moment it matters.
                    CharacterRing(count: note.length, limit: ValidationEngine.whatsNewCharacterLimit)
                        .padding(10)
                }

            issuesList
        }
    }

    /// Prefix every non-empty line with "• " (skipping lines that already carry
    /// one), so multi-line notes become an actual bullet list — not a single
    /// bullet glued to the front of the whole text.
    private func bulletized(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty, !line.hasPrefix("• ") else {
                    return line
                }
                return "• " + line
            }
            .joined(separator: "\n")
    }

    @ViewBuilder
    private var issuesList: some View {
        if !note.validationIssues.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(note.validationIssues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(
                            systemName: issue.severity == .error
                                ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(issue.severity == .error ? Color.red : .orange)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if issue.isMarkdown {
                            Button {
                                let cleaned = ValidationEngine().stripMarkdownToPlainText(note.localText)
                                state.updateLocalText(for: note.locale, text: cleaned)
                            } label: {
                                Label(L("Auto Fix"), systemImage: "wand.and.stars")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

}
