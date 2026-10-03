import SwiftUI

struct AIProfileHeader: View {
    let title: String
    let subtitle: String
    let isConfigured: Bool
    let provider: AIProvider
    let model: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isConfigured ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(isConfigured ? L("Configured (%@)", provider.displayName) : L("Not configured"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isConfigured ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule()
                        )
                        .foregroundStyle(isConfigured ? .green : .secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isConfigured {
                    Text(L("Model: %@", model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
    }
}

struct AIProfileFields: View {
    @Binding var provider: AIProvider
    @Binding var apiKey: String
    @Binding var baseURL: String
    @Binding var model: String
    let role: AIProfileRole
    let providers: [AIProvider]
    let onProviderChange: (AIProvider) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(L("Provider")).foregroundStyle(.secondary)
                Picker("", selection: $provider) {
                    ForEach(providers) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .onChange(of: provider) { _, newValue in
                    onProviderChange(newValue)
                }
            }
            GridRow {
                Text(L("API Key")).foregroundStyle(.secondary)
                SecureField(provider.apiKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text(L("Base URL")).foregroundStyle(.secondary)
                TextField(provider.defaultBaseURL.absoluteString, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text(L("Model")).foregroundStyle(.secondary)
                TextField(provider.defaultModel(for: role), text: $model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
