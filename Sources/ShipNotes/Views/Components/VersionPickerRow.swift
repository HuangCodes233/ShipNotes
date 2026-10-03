import SwiftUI

struct VersionPickerRow: View {
    @Environment(AppState.self) private var state
    @Binding var showNewVersionSheet: Bool

    var body: some View {
        @Bindable var state = state
        let versions = state.selectedAppId.flatMap { state.versionsByApp[$0] } ?? []
        return HStack(spacing: 8) {
            Picker(
                L("Version"),
                selection: Binding(
                    get: { state.selectedVersionId ?? "" },
                    set: { if !$0.isEmpty { state.selectVersion($0) } }
                )
            ) {
                ForEach(versions) { version in
                    if let date = version.createdDate {
                        Text("\(version.versionString) (\(date.formatted(date: .numeric, time: .omitted)))").tag(
                            version.id)
                    } else {
                        Text(version.versionString).tag(version.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Let the picker compress instead of forcing its intrinsic width;
            // the menu will truncate the version label rather than overflow.

            Button {
                state.refreshSelectedAppVersions()
            } label: {
                Label(L("Refresh Versions"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L("Refresh Versions"))
            .disabled(state.selectedAppId == nil || state.isLoadingRemote || state.isUsingMockData)

            Button {
                showNewVersionSheet = true
            } label: {
                Label(L("New Version"), systemImage: "plus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L("New Version…"))
            .disabled(state.selectedAppId == nil || state.isLoadingRemote)

            if let version = state.selectedVersion {
                VersionStateBadge(state: version.appStoreState)

                // The created-date and "not editable" label are secondary info;
                // they compress (truncation) before the picker/buttons do.
                if let date = version.createdDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .help(L("Created on %@", date.formatted(date: .complete, time: .omitted)))
                    .layoutPriority(-1)
                }

                if !version.canEditMetadata {
                    Label(L("Version not editable"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }

            if state.isLoadingRemote {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .lineLimit(1)
    }
}
