import SwiftUI

struct AppStoreConnectSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var accountName = ""
    @State private var issuerId = ""
    @State private var keyId = ""
    @State private var privateKeyPEM = ""
    // Hydrate once so switching tabs preserves unsaved form values.
    @State private var hasLoadedSummary = false

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("App Store Connect"), systemImage: state.isUsingMockData ? "key.slash" : "key.fill")
                    .font(.headline)
                Spacer()
                if state.isLoadingRemote {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(L(state.connectionStatus))
                .font(.callout)
                .foregroundStyle(state.isUsingMockData ? Color.secondary : Color.green)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L("Name"))
                        .foregroundStyle(.secondary)
                    TextField("App Store Connect", text: $accountName)
                }
                GridRow {
                    Text(L("Issuer ID"))
                        .foregroundStyle(.secondary)
                    TextField("00000000-0000-0000-0000-000000000000", text: $issuerId)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L("Key ID"))
                        .foregroundStyle(.secondary)
                    TextField("ABCD1234EF", text: $keyId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Private Key"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        importPrivateKey()
                    } label: {
                        Label(L("Import .p8"), systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                }

                TextEditor(text: $privateKeyPEM)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 96)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )

                if state.credentialSummary != nil
                    && privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Text(L("Private key is stored in Keychain. Leave this empty to keep the current key."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(role: .destructive) {
                    state.removeCredentials()
                    clearForm()
                } label: {
                    Label(L("Remove"), systemImage: "trash")
                }
                .disabled(state.credentialSummary == nil || state.isLoadingRemote)

                Spacer()

                Button {
                    Task { await state.testConnection() }
                } label: {
                    Label(L("Test"), systemImage: "network")
                }
                .disabled(state.credentialSummary == nil || state.isLoadingRemote)

                Button {
                    Task {
                        await state.saveCredentials(
                            name: accountName,
                            issuerId: issuerId,
                            keyId: keyId,
                            privateKeyPEM: privateKeyPEM
                        )
                        privateKeyPEM = ""
                        loadSummary()
                    }
                } label: {
                    Label(L("Save & Connect"), systemImage: "checkmark.circle")
                }
                .primarySyncButton()
                .disabled(
                    issuerId.isEmpty || keyId.isEmpty
                        || (state.credentialSummary == nil
                            && privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || state.isLoadingRemote)
            }
            Spacer()
        }
        .onAppear(perform: loadSummaryIfNeeded)
    }

    private func loadSummaryIfNeeded() {
        guard !hasLoadedSummary else { return }
        hasLoadedSummary = true
        loadSummary()
    }

    private func loadSummary() {
        guard let summary = state.credentialSummary else { return }
        accountName = summary.name
        issuerId = summary.issuerId
        keyId = summary.keyId
    }
    private func clearForm() {
        accountName = ""
        issuerId = ""
        keyId = ""
        privateKeyPEM = ""
    }

    private func importPrivateKey() {
        PrivateKeyImporter.present { result in
            switch result {
            case .success(let key): privateKeyPEM = key
            case .failure(let error): state.handleError(error)
            }
        }
    }
}
