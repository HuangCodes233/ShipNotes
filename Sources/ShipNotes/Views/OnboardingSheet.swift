import SwiftUI

/// Shown once on first launch when the app is still in mock-data mode.
/// Three-step quick-start that pushes the user toward Settings → Account.
/// Dismissed manually; persistence handled via `@AppStorage` in ContentView.
struct OnboardingSheet: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Welcome to ShipNotes")).font(.title2.bold())
                Text(L("Push App Store release notes from local files to App Store Connect."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Three steps to connect your account"))
                .font(.headline)

            step(
                number: "1",
                title: L("Generate an App Store Connect API Key"),
                body: L("appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → Generate.")
            )
            step(
                number: "2",
                title: L("Copy your Issuer ID + Key ID, download the .p8 file"),
                body: L("The .p8 file can be downloaded once — keep it somewhere safe.")
            )
            step(
                number: "3",
                title: L("Paste into Settings → Account, then Save & Connect"),
                body: L("ShipNotes stores the private key in Keychain. The Test button confirms the connection works.")
            )

            Divider().padding(.vertical, 2)

            Text(L("Until you connect, ShipNotes runs against sample data so you can explore the interface."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Explore the demo first")) {
                onDismiss()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                onDismiss()
                dismiss()
                openSettings()
            } label: {
                Label(L("Open Settings"), systemImage: "gearshape")
            }
            .keyboardShortcut(.defaultAction)
            .primarySyncButton()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
