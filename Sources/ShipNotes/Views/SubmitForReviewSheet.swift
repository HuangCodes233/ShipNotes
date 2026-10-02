import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Submit-for-review confirmation sheet. Shows what's about to be submitted
/// (app, version, build, locale readiness) plus a release-type picker, then
/// kicks off `AppState.submitSelectedVersionForReview`.
///
/// First-time app submissions still need to be set up via the App Store
/// Connect web UI (screenshots, pricing, age rating). For subsequent version
/// updates this sheet replaces the entire web-UI submit flow.
struct SubmitForReviewSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var releaseType: AppState.ReleaseType = .afterApproval
    @State private var localError: String?
    @State private var showBuildPickerSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
            }
            Divider()
            footer
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 500, idealHeight: 620)
        .sheet(isPresented: $showBuildPickerSheet) {
            BuildPickerSheet()
                .environment(state)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L("Submit for Review"), systemImage: "paperplane.fill")
                .font(.headline)
            Spacer()
            if state.isSubmittingForReview {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Submitting will send this version to Apple App Review. ShipNotes will run the standard 3-step flow: create submission → attach version → submit."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            summary

            preflightChecks

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Release Type")).font(.headline)
                Picker("", selection: $releaseType) {
                    Text(L("Release manually after approval")).tag(AppState.ReleaseType.manual)
                    Text(L("Release automatically after approval")).tag(AppState.ReleaseType.afterApproval)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if let err = localError {
                errorSection(for: err)
            } else if state.offerPromoteAfterSubmit {
                promoteOffer
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func errorSection(for err: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            if Self.shouldShowASCLink(for: err), let appId = state.selectedAppId {
                diagnosticWizard(appId: appId)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func diagnosticWizard(appId: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                Text(L("409 Diagnostic Checklist (App Store Connect)"))
                    .font(.subheadline.bold())
            }

            Text(L("Apple's API returns generic 409 error when required metadata or build verification is missing. Check the following items:"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                checklistBullet(
                    icon: "lock.shield.fill",
                    title: L("Export Compliance"),
                    desc: L("Check if the attached build requires encryption compliance confirmation (yellow badge in TestFlight/ASC).")
                )
                checklistBullet(
                    icon: "photo.stack.fill",
                    title: L("Required Screenshots"),
                    desc: L("Ensure mandatory 6.9\"/6.5\" iPhone or 13\" iPad screenshots are provided for all target locales.")
                )
                checklistBullet(
                    icon: "hand.raised.fill",
                    title: L("App Privacy Responses"),
                    desc: L("Ensure the Data Nutrition / App Privacy questionnaire is completed in App Store Connect.")
                )
                checklistBullet(
                    icon: "person.crop.circle.badge.checkmark",
                    title: L("Age Rating & Review Info"),
                    desc: L("Ensure age rating questionnaire, contact info (phone/email), and demo login credentials are filled.")
                )
                checklistBullet(
                    icon: "link",
                    title: L("Privacy Policy URL"),
                    desc: L("Ensure a valid Privacy Policy URL is entered if your app requires account login or purchases.")
                )
            }
            .padding(.vertical, 4)

            HStack(spacing: 10) {
                Button {
                    Self.openASCApp(appId: appId)
                } label: {
                    Label(L("Open in App Store Connect"), systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)

                Button {
                    Self.openASCTestFlight(appId: appId)
                } label: {
                    Label(L("Open Builds / Compliance in ASC"), systemImage: "shippingbox.fill")
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private func checklistBullet(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private static func shouldShowASCLink(for message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("409")
            || lowered.contains("state_error")
            || lowered.contains("entity_state_invalid")
            || lowered.contains("not in valid state")
            || lowered.contains("cannot be reviewed")
    }

    private static func openASCApp(appId: String) {
        #if canImport(AppKit)
        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)/distribution") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private static func openASCTestFlight(appId: String) {
        #if canImport(AppKit)
        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)/testflight/ios") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private var promoteOffer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Submitted for review."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(L("Create a Search results campaign for this app on Apple Ads?"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("You're about to submit")).font(.headline)
            HStack(spacing: 6) {
                AppIconView(app: state.selectedApp, size: 20, cornerRadius: 5)
                Text(state.selectedApp?.name ?? "—").bold()
                Text("· v\(state.selectedVersion?.versionString ?? "—")")
                    .foregroundStyle(.secondary)
            }
            if let attached = state.attachedBuildForSelectedVersion {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.secondary)
                    Text(L("Build %@", attached.buildNumber))
                    Text("·")
                    Text(attached.processingState.displayName)
                        .foregroundStyle(attached.processingState.canBeAttached ? .green : .orange)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var preflightChecks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Pre-flight Checks")).font(.headline)
            check(
                ok: state.canSubmitSelectedForReview,
                label: versionStateChecklistLabel
            )
            HStack(spacing: 8) {
                check(
                    ok: state.attachedBuildForSelectedVersion != nil,
                    label: state.attachedBuildForSelectedVersion != nil
                        ? L("Build attached")
                        : L("No build attached — Apple will reject with 409")
                )
                if state.attachedBuildForSelectedVersion == nil, !state.isUsingMockData {
                    Button {
                        showBuildPickerSheet = true
                    } label: {
                        Text(L("Attach Build…"))
                    }
                    .controlSize(.mini)
                }
            }
            check(
                ok: state.releaseNotesReadyForReviewSubmission,
                label: state.releaseNotesReviewChecklistLabel
            )
            check(
                ok: state.screenshotReadyForSubmission,
                label: state.screenshotChecklistLabel
            )
        }
    }

    private var versionStateChecklistLabel: String {
        guard let version = state.selectedVersion else {
            return L("No version selected")
        }
        if version.appStoreState.isSubmittedForReview {
            return L("Version is already submitted")
        }
        return version.canEditMetadata
            ? L("Version is editable")
            : L("Version is not in an editable state")
    }

    private func check(ok: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label).font(.callout)
        }
    }

    private var canSubmit: Bool {
        state.canSubmitSelectedForReview
            && !state.isSubmittingForReview
            && (state.isUsingMockData || state.attachedBuildForSelectedVersion != nil)
    }

    private var footer: some View {
        HStack {
            if state.offerPromoteAfterSubmit {
                Button(L("Not now")) {
                    state.offerPromoteAfterSubmit = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    state.offerPromoteAfterSubmit = false
                    dismiss()
                    state.presentPromoteVersionSheet()
                } label: {
                    Label(L("Promote…"), systemImage: "megaphone.fill")
                }
                .keyboardShortcut(.defaultAction)
                .primarySyncButton()
            } else {
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    submit()
                } label: {
                    Label(L("Submit for Review"), systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .primarySyncButton()
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() {
        localError = nil
        Task {
            let submitted = await state.submitSelectedVersionForReview(releaseType: releaseType)
            if !submitted {
                localError = state.lastError?.message ?? L("The version was not submitted for review.")
            } else if !state.offerPromoteAfterSubmit {
                dismiss()
            }
        }
    }
}
