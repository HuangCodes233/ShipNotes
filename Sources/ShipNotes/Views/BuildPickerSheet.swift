import SwiftUI

/// Pick which uploaded build to attach to the currently-selected App Store
/// version. Bypasses the App Store Connect web UI's "构建版本 → 添加构建版本"
/// dance. Calls `PATCH /v1/appStoreVersions/{id}/relationships/build`.
struct BuildPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var isAttaching = false
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            if let localError {
                // The main window's error banner sits behind this sheet.
                Label(localError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            footer
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 380, idealHeight: 460)
        .task {
            await state.loadBuildsForSelectedVersion()
            // Pre-select whatever is currently attached on the server.
            selection = state.attachedBuildForSelectedVersion?.id
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L("Select Build for Version"), systemImage: "shippingbox")
                .font(.headline)
            if let v = state.selectedVersion {
                Text("· v\(v.versionString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isLoadingBuilds {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        let builds = state.selectedVersionId.flatMap { state.buildsByVersion[$0] } ?? []
        if state.isLoadingBuilds && builds.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if builds.isEmpty {
            ContentUnavailableView {
                Label(L("No builds found"), systemImage: "shippingbox")
            } description: {
                Text(
                    L(
                        "Upload a build via Xcode → Product → Archive → Distribute App, or Transporter. Once Apple finishes processing, it will show up here."
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(builds) { build in
                    BuildRow(
                        build: build,
                        isAttached: state.attachedBuildForSelectedVersion?.id == build.id
                    )
                    .tag(build.id)
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)

            if let attached = state.attachedBuildForSelectedVersion {
                Button(role: .destructive) {
                    Task {
                        isAttaching = true
                        localError = nil
                        let detached = await state.setBuildForSelectedVersion(nil)
                        isAttaching = false
                        if detached {
                            dismiss()
                        } else {
                            localError = state.lastError?.message ?? L("The build was not changed.")
                        }
                    }
                } label: {
                    Label(L("Detach"), systemImage: "minus.circle")
                }
                .disabled(isAttaching || state.isLoadingBuilds)
                .help(L("Current build: %@", attached.buildNumber))
            }

            Spacer()

            Button {
                guard let id = selection else { return }
                Task {
                    isAttaching = true
                    localError = nil
                    let attached = await state.setBuildForSelectedVersion(id)
                    isAttaching = false
                    if attached {
                        dismiss()
                    } else {
                        localError = state.lastError?.message ?? L("The build was not changed.")
                    }
                }
            } label: {
                if isAttaching {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("Attach Build"), systemImage: "checkmark.circle")
                }
            }
            .keyboardShortcut(.defaultAction)
            .primarySyncButton()
            .disabled(selection == nil || isAttaching || state.isLoadingBuilds || !canAttachSelection)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Disable Attach when the user selects an INVALID / still-PROCESSING build.
    private var canAttachSelection: Bool {
        guard let id = selection,
            let builds = state.selectedVersionId.flatMap({ state.buildsByVersion[$0] }),
            let chosen = builds.first(where: { $0.id == id })
        else { return false }
        return chosen.processingState.canBeAttached
    }
}

private struct BuildRow: View {
    let build: Build
    let isAttached: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isAttached ? "checkmark.circle.fill" : "shippingbox")
                .foregroundStyle(isAttached ? Color.green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L("Build %@", build.buildNumber))
                        .font(.callout.monospaced())
                    stateBadge
                }
                if let date = build.uploadedDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let expires = build.expirationDate {
                Text(L("Expires %@", expires.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(stateColor).frame(width: 6, height: 6)
            Text(build.processingState.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(stateColor.opacity(0.15), in: Capsule())
    }

    private var stateColor: Color {
        switch build.processingState {
        case .valid: .green
        case .processing: .orange
        case .invalid, .failed: .red
        case .unknown: .gray
        }
    }
}
