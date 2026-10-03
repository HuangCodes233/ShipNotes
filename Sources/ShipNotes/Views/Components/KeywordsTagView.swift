import SwiftUI

struct KeywordsTagView: View {
    @Binding var keywordsText: String
    @State private var newTagText: String = ""

    private var tags: [String] { KeywordList.tags(in: keywordsText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                // Offsets, not the text, identify tags: a keyword may appear twice.
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption.weight(.medium))
                        Button {
                            removeTag(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Remove keyword %@", tag))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                TextField(L("Add keyword..."), text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }

                Button(L("Add")) { addTag() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
            }
        }
    }

    private func removeTag(at index: Int) {
        keywordsText = KeywordList.removing(at: index, from: keywordsText)
    }

    private func addTag() {
        guard let updated = KeywordList.adding(newTagText, to: keywordsText) else { return }
        keywordsText = updated
        newTagText = ""
    }
}
