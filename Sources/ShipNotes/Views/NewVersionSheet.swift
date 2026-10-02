import SwiftUI

/// Small sheet for creating a new App Store version directly from ShipNotes,
/// so the user doesn't have to bounce out to the App Store Connect web UI.
/// Calls `POST /v1/appStoreVersions`; the configured API key must be at least
/// **App Manager** role to create versions.
struct NewVersionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let defaultPlatform: Platform
    /// Pre-fill suggestion based on the current selected version (last numeric
    /// component bumped by 1). User can freely edit before submitting.
    let suggestedVersion: String

    @State private var versionString: String = ""
    @State private var platform: Platform = .ios
    @State private var isSubmitting = false
    @State private var localError: String?
    @State private var versionWasEdited = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 500)
        .onAppear {
            platform = defaultPlatform
            if versionString.isEmpty {
                versionString = suggestedVersion
            }
        }
        .task(id: state.selectedAppId) {
            await state.refreshVersionCreationContext()
            if !versionWasEdited, let candidate = uploadedVersionCandidates.first {
                versionString = candidate.version
            }
        }
        .onChange(of: platform) {
            if !versionWasEdited, let candidate = uploadedVersionCandidates.first {
                versionString = candidate.version
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L("New Version"), systemImage: "plus.circle.fill")
                .font(.headline)
            Spacer()
            if isSubmitting || state.isLoadingVersionCreationContext {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Create a new editable version on App Store Connect. ShipNotes will switch to it automatically once created."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L("Version")).foregroundStyle(.secondary)
                    TextField("1.8.0", text: Binding(
                        get: { versionString },
                        set: {
                            versionString = $0
                            versionWasEdited = true
                        }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L("Platform")).foregroundStyle(.secondary)
                    Picker("", selection: $platform) {
                        ForEach(Platform.allCases) { platform in
                            Text(platform.displayLabel).tag(platform)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
            }

            Text(L("Your API key needs at least App Manager role to create versions. Version must be greater than the latest released version (e.g., 1.7.0 → 1.8.0)."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let err = localError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = state.versionCreationContextError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !uploadedVersionCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Uploaded versions not yet created on the App Store"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(uploadedVersionCandidates.prefix(8))) { summary in
                            Button {
                                versionString = summary.version
                                versionWasEdited = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "shippingbox")
                                        .foregroundStyle(.blue)
                                    Text(summary.version)
                                        .font(.caption.monospaced().weight(.semibold))
                                    Text(L("Build %@", summary.latestBuild.buildNumber))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let date = summary.latestBuild.uploadedDate {
                                        Text(date, format: .dateTime.month().day())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(summary.latestBuild.processingState.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("Use version %@", summary.version))
                            .padding(.vertical, 4)

                            if summary.id != uploadedVersionCandidates.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if !unreleasedStoreVersions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Unreleased App Store versions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(unreleasedStoreVersions) { version in
                            HStack(spacing: 8) {
                                Text("\(platform.displayLabel) \(version.versionString)")
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(version.appStoreState.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                            if version.id != unreleasedStoreVersions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if let latestReleasedVersion {
                Text(L("Latest released version: %@", latestReleasedVersion.versionString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                submit()
            } label: {
                Label(L("Create"), systemImage: "checkmark.circle")
            }
            .keyboardShortcut(.defaultAction)
            .primarySyncButton()
            .disabled(versionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() {
        localError = nil
        isSubmitting = true
        Task {
            let created = await state.createVersion(versionString: versionString, platform: platform.apiValue)
            isSubmitting = false
            if created {
                dismiss()
            } else {
                localError = state.lastError?.message ?? L("The version was not created.")
            }
        }
    }

    /// All versions for the current app, sorted newest first.
    private var allVersions: [ReleaseVersion] {
        (state.versionsByApp[state.selectedAppId ?? ""] ?? [])
            .filter { Platform(displayName: $0.platform) == platform }
            .sorted { $0.versionString.compare($1.versionString, options: .numeric) == .orderedDescending }
    }

    private var unreleasedStoreVersions: [ReleaseVersion] {
        allVersions.filter { !Self.releasedStates.contains($0.appStoreState) }
    }

    private var latestReleasedVersion: ReleaseVersion? {
        allVersions.first { Self.releasedStates.contains($0.appStoreState) }
    }

    private var uploadedVersionCandidates: [UploadedVersionSummary] {
        let appId = state.selectedAppId ?? ""
        let existingVersions = Set(allVersions.map(\.versionString))
        let matchingBuilds = (state.uploadedBuildsByApp[appId] ?? []).filter { build in
            guard let buildPlatform = build.platform else { return true }
            return buildPlatform == platform.apiValue
        }
        let grouped = Dictionary(grouping: matchingBuilds) { $0.marketingVersion }

        return grouped.compactMap { version, builds in
            guard let version, !version.isEmpty, !existingVersions.contains(version),
                  let latestBuild = builds.max(by: {
                      ($0.uploadedDate ?? .distantPast) < ($1.uploadedDate ?? .distantPast)
                  }) else { return nil }
            return UploadedVersionSummary(version: version, latestBuild: latestBuild)
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    private static let releasedStates: Set<AppStoreVersionState> = [
        .accepted,
        .pendingAppleRelease,
        .pendingDeveloperRelease,
        .preorderReadyForSale,
        .readyForSale,
        .developerRemovedFromSale,
        .removedFromSale,
        .replacedWithNewVersion
    ]

    static func defaultPlatform(
        selectedVersion: ReleaseVersion?,
        selectedAppId: String?,
        versionsByApp: [String: [ReleaseVersion]]
    ) -> Platform {
        let display = selectedVersion?.platform
            ?? selectedAppId.flatMap { versionsByApp[$0]?.first?.platform }
            ?? "iOS"
        return Platform(displayName: display)
    }

    /// Pick a sensible default version string: the highest existing version
    /// for this app, with its trailing numeric component bumped by 1.
    /// "3.0.1" -> "3.0.2", "1.7" -> "1.8", "2.0" -> "2.1".
    static func suggestedNextVersion(
        selectedVersion: ReleaseVersion?,
        selectedAppId: String?,
        versionsByApp: [String: [ReleaseVersion]]
    ) -> String {
        let candidate = selectedAppId
            .flatMap { versionsByApp[$0] }?
            .max(by: { $0.versionString.compare($1.versionString, options: .numeric) == .orderedAscending })?
            .versionString
            ?? selectedVersion?.versionString
            ?? ""
        return bumpTrailingNumber(in: candidate)
    }

    private static func bumpTrailingNumber(in version: String) -> String {
        let parts = version.split(separator: ".").map(String.init)
        guard !parts.isEmpty, let last = parts.last, let number = Int(last) else {
            return ""
        }
        var bumped = parts
        bumped[bumped.count - 1] = String(number + 1)
        return bumped.joined(separator: ".")
    }

    enum Platform: String, CaseIterable, Identifiable, Hashable {
        case ios
        case macOS
        case tvOS
        case visionOS

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .ios: return "iOS"
            case .macOS: return "macOS"
            case .tvOS: return "tvOS"
            case .visionOS: return "visionOS"
            }
        }

        var apiValue: String {
            switch self {
            case .ios: return "IOS"
            case .macOS: return "MAC_OS"
            case .tvOS: return "TV_OS"
            case .visionOS: return "VISION_OS"
            }
        }

        init(displayName: String) {
            switch displayName.lowercased() {
            case "macos": self = .macOS
            case "tvos": self = .tvOS
            case "visionos", "xros": self = .visionOS
            default: self = .ios
            }
        }
    }
}

private struct UploadedVersionSummary: Identifiable {
    let version: String
    let latestBuild: Build

    var id: String { version }
}
