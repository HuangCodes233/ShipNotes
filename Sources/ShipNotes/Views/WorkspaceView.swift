import SwiftUI

struct WorkspaceView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var showNewVersionSheet = false
    @State private var showBuildPickerSheet = false
    @State private var showSubmitForReviewSheet = false

    var body: some View {
        if state.selectedAppId == nil {
            ContentUnavailableView {
                Label(L("Select an App"), systemImage: "hand.point.up.left")
            } description: {
                Text(L("Choose an app from the sidebar to manage its release notes."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            mainWorkspace
        }
    }

    private var mainWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            versionPicker
            buildRow
            sourceArea
            LocaleTable()
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.loadFolder(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropZoneOverlay(isTargeted: isDropTargeted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
        .sheet(isPresented: $showNewVersionSheet) {
            NewVersionSheet(
                defaultPlatform: defaultNewVersionPlatform(),
                suggestedVersion: suggestedNextVersion()
            )
            .environment(state)
        }
        .sheet(isPresented: $showBuildPickerSheet) {
            BuildPickerSheet()
                .environment(state)
        }
        .sheet(isPresented: $showSubmitForReviewSheet) {
            SubmitForReviewSheet()
                .environment(state)
        }
    }

    @ViewBuilder
    private var buildRow: some View {
        // Build attachment is only meaningful in live (non-mock) mode and
        // when an editable version is selected.
        if !state.isUsingMockData, let version = state.selectedVersion {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                if let attached = state.attachedBuildForSelectedVersion {
                    Text(L("Build %@", attached.buildNumber))
                        .font(.callout)
                        .lineLimit(1)
                } else {
                    Text(L("No build attached"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showBuildPickerSheet = true
                } label: {
                    Label(L("Attach Build…"), systemImage: "shippingbox.and.arrow.backward")
                }
                .controlSize(.small)
                .disabled(state.isLoadingBuilds || !version.canEditMetadata)
                .help(version.canEditMetadata ? L("Choose which uploaded build to attach to this version.") : L("This version's metadata is locked."))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassSurface(cornerRadius: 10)
        }
    }

    private func defaultNewVersionPlatform() -> NewVersionSheet.Platform {
        let display = state.selectedVersion?.platform
            ?? state.selectedAppId.flatMap { state.versionsByApp[$0]?.first?.platform }
            ?? "iOS"
        return NewVersionSheet.Platform(displayName: display)
    }

    /// Pick a sensible default version string: the highest existing version
    /// for this app, with its trailing numeric component bumped by 1.
    /// "3.0.1" -> "3.0.2", "1.7" -> "1.8", "2.0" -> "2.1". Falls back to "" when
    /// the current version doesn't end in a number.
    private func suggestedNextVersion() -> String {
        NewVersionSheet.suggestedNextVersion(
            selectedVersion: state.selectedVersion,
            selectedAppId: state.selectedAppId,
            versionsByApp: state.versionsByApp
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(app: state.selectedApp, size: 48, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.selectedApp?.name ?? L("No app selected"))
                    .font(.title2).bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.selectedApp?.bundleId ?? "-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var versionPicker: some View {
        // When the workspace is narrow, drop the Submit button to a compact
        // icon-only form so the version picker + button row never overflows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                VersionPickerRow(showNewVersionSheet: $showNewVersionSheet)
                Spacer(minLength: 8)
                submitForReviewButton(compact: false)
            }

            HStack(spacing: 8) {
                VersionPickerRow(showNewVersionSheet: $showNewVersionSheet)
                Spacer(minLength: 4)
                submitForReviewButton(compact: true)
            }

            VersionPickerRow(showNewVersionSheet: $showNewVersionSheet)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func submitForReviewButton(compact: Bool) -> some View {
        if !state.isUsingMockData, state.selectedVersion?.canEditMetadata == true {
            Button {
                showSubmitForReviewSheet = true
            } label: {
                if compact {
                    Label(L("Submit for Review"), systemImage: "paperplane.fill")
                        .labelStyle(.iconOnly)
                } else {
                    Label(L("Submit for Review"), systemImage: "paperplane.fill")
                        .lineLimit(1)
                }
            }
            .controlSize(.small)
            .secondaryGlassButton()
            .disabled(state.isSubmittingForReview)
            .help(L("Submit this version to Apple App Review without leaving ShipNotes."))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var sourceArea: some View {
        if state.sourceFolder == nil {
            dropZone
        } else {
            pathCapsule
        }
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Drag a project folder, release-notes folder, or file here"))
                    .font(.callout.weight(.medium))
                Text(state.isUsingMockData ? L("Or use Import Folder in the toolbar. Currently showing sample data.") : L("Or use Import Folder in the toolbar. Current remote notes are loaded from App Store Connect."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.presentImportPicker() } label: {
                Label(L("Import"), systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
            .secondaryGlassButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .glassSurface(cornerRadius: 12)
    }

    private var pathCapsule: some View {
        URLPathCapsule(
            url: state.sourceFolder!,
            iconName: "doc.text.fill",
            onRefresh: {
                if let url = state.sourceFolder {
                    state.loadFolder(url)
                }
            },
            onChange: {
                state.presentImportPicker()
            }
        )
    }
}
