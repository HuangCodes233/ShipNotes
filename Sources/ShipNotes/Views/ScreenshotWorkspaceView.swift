import ImageIO
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ScreenshotWorkspaceView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var showAllIssues = false

    var body: some View {
        if state.selectedAppId == nil {
            SelectAppEmptyState(description: L("Choose an app from the sidebar before checking screenshots."))
        } else {
            content
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    sourceArea
                    if let scan = state.screenshotScan {
                        summary(
                            scan,
                            blockingIssueCount: state.screenshotBlockingIssueCount,
                            warningCount: state.screenshotWarningCount
                        )
                        readinessPanel(
                            groups: state.screenshotCoverageGroups,
                            blockingIssueCount: state.screenshotBlockingIssueCount,
                            warningCount: state.screenshotWarningCount,
                            previewControls: state.screenshotPreviewControlsState
                        )
                        localeCoverage(
                            groups: state.screenshotCoverageGroups,
                            visibleSlots: state.visibleScreenshotSlots,
                            missingByLocale: state.missingRequirementsByLocale
                        )
                        issueList(state.screenshotIssues)
                        screenshotGrid(
                            groups: state.screenshotCoverageGroups,
                            visibleSlots: state.visibleScreenshotSlots,
                            missingByLocale: state.missingRequirementsByLocale
                        )
                    } else {
                        emptyState
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: state.screenshotFocusTargetID) { _, targetID in
                guard let targetID else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.loadScreenshotsFolder(url)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .dropZoneOverlay(isTargeted: isDropTargeted)
        .sheet(
            isPresented: Binding(
                get: { state.pendingScreenshotReplacement != nil },
                set: { presented in
                    if !presented {
                        state.dismissScreenshotReplacementPreview()
                    }
                }
            )
        ) {
            if let plan = state.pendingScreenshotReplacement {
                ScreenshotReplacementPreviewSheet(plan: plan)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(app: state.selectedApp, size: 48, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Screenshots"))
                    .font(.title2).bold()
                Text(state.selectedApp?.name ?? L("No app selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            // Requirement pills can be numerous; wrap to a scrollable row so
            // they never push the app name off-screen on narrow windows.
            if !state.requiredScreenshotSlotGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.requiredScreenshotSlotGroups) { requirement in
                            RequirementPill(requirement: requirement)
                        }
                    }
                }
                .frame(maxWidth: 360)
            }
        }
    }

    @ViewBuilder
    private var sourceArea: some View {
        if let folder = state.screenshotFolder {
            URLPathCapsule(
                url: folder,
                subtitle: state.screenshotScan.map { "\($0.sourceKind.displayName) · \($0.root.path)" },
                iconName: "folder.fill",
                onRefresh: {
                    state.loadScreenshotsFolder(folder)
                },
                onChange: {
                    state.presentScreenshotPicker()
                }
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("No screenshots imported"), systemImage: "photo.stack")
        } description: {
            Text(L("Drag a screenshot folder here"))
            Text(
                L(
                    "Choose a folder that contains App Store screenshots. Nested locale folders like en-US or zh-Hans are supported."
                ))
        } actions: {
            Button {
                state.presentScreenshotPicker()
            } label: {
                Label(L("Import Screenshots"), systemImage: "folder.badge.plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func summary(
        _ scan: ScreenshotScan,
        blockingIssueCount: Int,
        warningCount: Int
    ) -> some View {
        // Use a horizontal ScrollView so the metric cards never squeeze/wrap
        // on narrow windows; they scroll instead.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SummaryMetric(
                    title: L("Total"), value: "\(scan.assets.count)", systemImage: "photo.stack", color: .blue)
                SummaryMetric(
                    title: L("Ready"), value: "\(scan.readyCount)", systemImage: "checkmark.circle.fill", color: .green)
                SummaryMetric(
                    title: L("Blocking"), value: "\(blockingIssueCount)", systemImage: "xmark.octagon.fill",
                    color: blockingIssueCount == 0 ? .green : .red)
                SummaryMetric(
                    title: L("Warnings"), value: "\(warningCount)", systemImage: "exclamationmark.triangle.fill",
                    color: warningCount == 0 ? .green : .orange)
                if scan.skippedCount > 0 {
                    SummaryMetric(
                        title: L("Skipped"), value: "\(scan.skippedCount)", systemImage: "questionmark.circle.fill",
                        color: .secondary)
                }
            }
        }
    }

    private func readinessPanel(
        groups: [ScreenshotLocaleGroup],
        blockingIssueCount: Int,
        warningCount: Int,
        previewControls: ScreenshotPreviewControlsState
    ) -> some View {
        let readyForSubmission = blockingIssueCount == 0
        let checklistLabel: String = {
            if blockingIssueCount == 0 {
                if warningCount == 0 {
                    return L("Screenshots ready")
                }
                return L("Screenshots ready with %d warning(s)", warningCount)
            }
            return L("Screenshots have %d blocking issue(s)", blockingIssueCount)
        }()

        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    readinessTitle(
                        readyForSubmission: readyForSubmission,
                        checklistLabel: checklistLabel
                    )
                    Spacer(minLength: 12)
                    Text(L("%d locale(s)", groups.count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    previewActions(previewControls)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        readinessTitle(
                            readyForSubmission: readyForSubmission,
                            checklistLabel: checklistLabel
                        )
                        Spacer(minLength: 8)
                        Text(L("%d locale(s)", groups.count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        previewActions(previewControls)
                    }
                }
            }

            if state.canConfigureScreenshotIPadSupport {
                Divider()
                    .opacity(0.45)
                iPadRequirementControl
            }

            screenshotPreviewDisabledReasons(previewControls)

            if let summary = state.screenshotUploadSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 8)
    }

    private func readinessTitle(
        readyForSubmission: Bool,
        checklistLabel: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: readyForSubmission ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(readyForSubmission ? .green : .orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Screenshot Pre-flight"))
                    .font(.headline)
                Text(checklistLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func previewActions(_ controls: ScreenshotPreviewControlsState) -> some View {
        HStack(spacing: 8) {
            if state.isPreparingScreenshotReplacement || state.isUploadingScreenshots {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                state.uploadSelectedScreenshotLocale()
            } label: {
                Label(L("Preview Selected"), systemImage: "eye")
            }
            .controlSize(.small)
            .disabled(controls.selectedDisabledReason != nil)
            .help(
                controls.selectedDisabledReason
                    ?? L("Preview screenshot replacements for the selected locale.")
            )

            Button {
                state.uploadAllScreenshots()
            } label: {
                Label(L("Preview All"), systemImage: "eye.fill")
            }
            .controlSize(.small)
            .disabled(controls.allDisabledReason != nil)
            .help(
                controls.allDisabledReason
                    ?? L("Preview screenshot replacements for every ready locale.")
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func screenshotPreviewDisabledReasons(_ controls: ScreenshotPreviewControlsState) -> some View {
        let selectedReason = controls.selectedDisabledReason
        let allReason = controls.allDisabledReason
        if selectedReason != nil || allReason != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let selectedReason {
                    Label("\(L("Preview Selected")): \(selectedReason)", systemImage: "info.circle")
                }
                if let allReason {
                    Label("\(L("Preview All")): \(allReason)", systemImage: "info.circle")
                }
            }
            .font(.caption2)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iPadRequirementControl: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "ipad")
                .foregroundStyle(state.screenshotRequiresIPad ? .orange : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("iPad Screenshots"))
                    .font(.caption.weight(.semibold))
                Text(
                    state.screenshotIPadRequirementSummary + " " + state.selectedScreenshotIPadSupportDetection.summary
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer(minLength: 12)
            Picker(
                "",
                selection: Binding(
                    get: { state.screenshotIPadSupportOverride },
                    set: { state.setScreenshotIPadSupportOverride($0) }
                )
            ) {
                ForEach(ScreenshotIPadSupportOverride.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 280)
            .help(L("Choose whether iPad screenshots are required for this app."))
        }
    }

    private func localeCoverage(
        groups: [ScreenshotLocaleGroup],
        visibleSlots: [ScreenshotDeviceSlot],
        missingByLocale: [String: [ScreenshotSlotRequirement]]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Locale Coverage"))
                    .font(.headline)
                Spacer()
                Text(L("%d locale(s)", groups.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.isLoadingRemoteScreenshotCounts {
                    ProgressView()
                        .controlSize(.small)
                        .help(L("Loading current App Store screenshot counts."))
                }
                Button {
                    state.refreshRemoteScreenshotCounts()
                } label: {
                    Image(systemName: "cloud")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Refresh current App Store screenshot counts."))
                .controlSize(.small)
                .help(L("Refresh current App Store screenshot counts."))
                .disabled(state.screenshotScan == nil || state.isUsingMockData)
            }

            // Wrap the coverage table in a horizontal ScrollView so wide tables
            // (many device slots) scroll instead of clipping the Issues column.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    coverageHeader(visibleSlots: visibleSlots)
                    ForEach(groups) { group in
                        coverageRow(
                            group,
                            visibleSlots: visibleSlots,
                            missingRequirements: missingByLocale[group.locale] ?? []
                        )
                        if group.id != groups.last?.id {
                            Divider()
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private func coverageHeader(visibleSlots: [ScreenshotDeviceSlot]) -> some View {
        HStack(spacing: 8) {
            Text(L("Locale"))
                .frame(width: 96, alignment: .leading)
            ForEach(visibleSlots) { slot in
                Text(slot.displayName)
                    .frame(width: 96, alignment: .center)
            }
            Text(L("Online"))
                .frame(width: 64, alignment: .center)
            Spacer()
            Text(L("Issues"))
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    private func coverageRow(
        _ group: ScreenshotLocaleGroup,
        visibleSlots: [ScreenshotDeviceSlot],
        missingRequirements: [ScreenshotSlotRequirement]
    ) -> some View {
        return HStack(spacing: 8) {
            Button {
                state.selectedScreenshotLocale = group.locale
            } label: {
                Text(group.locale)
                    .font(.callout.weight(.semibold))
                    .frame(width: 96, alignment: .leading)
            }
            .buttonStyle(.plain)

            ForEach(visibleSlots) { slot in
                SlotCountBadge(
                    count: group.count(for: slot),
                    isMissingRequirement: !group.isUnassigned && missingRequirements.contains { $0.contains(slot) }
                )
                .frame(width: 96)
            }
            Text(remoteScreenshotCountText(for: group))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 64, alignment: .center)
                .help(L("Current App Store screenshot count."))
            Spacer()
            Text(
                group.isUnassigned
                    ? L("Needs locale")
                    : (missingRequirements.isEmpty ? L("OK") : L("%d missing sizes", missingRequirements.count))
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(group.isUnassigned ? .orange : (missingRequirements.isEmpty ? .green : .orange))
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(state.selectedScreenshotLocale == group.locale ? Color.accentColor.opacity(0.10) : Color.clear)
        .id(state.screenshotLocaleFocusID(group.locale))
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedScreenshotLocale = group.locale
        }
    }

    private let maxDisplayedIssues = 8

    @ViewBuilder
    private func issueList(_ issues: [ScreenshotIssue]) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Screenshot Issues"))
                        .font(.headline)
                    Spacer()
                    Text(L("%d issue(s)", issues.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    let displayedIssues = showAllIssues ? issues : Array(issues.prefix(maxDisplayedIssues))
                    ForEach(displayedIssues) { issue in
                        Button {
                            state.selectScreenshotIssue(issue)
                        } label: {
                            ScreenshotIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .help(L("Show this issue in the screenshot list."))
                        if issue.id != displayedIssues.last?.id {
                            Divider()
                        }
                    }
                    if issues.count > maxDisplayedIssues {
                        Divider()
                        Button {
                            showAllIssues.toggle()
                        } label: {
                            Text(
                                showAllIssues
                                    ? L("Show fewer issues")
                                    : L("Show all %d issue(s)", issues.count)
                            )
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }

    private func screenshotGrid(
        groups: [ScreenshotLocaleGroup],
        visibleSlots: [ScreenshotDeviceSlot],
        missingByLocale: [String: [ScreenshotSlotRequirement]]
    ) -> some View {
        let group = groups.first { $0.locale == state.selectedScreenshotLocale } ?? groups.first
        let locale = group?.locale
        let missing = locale.flatMap { missingByLocale[$0] } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.map { L("Screenshots · %@", $0.locale) } ?? L("Screenshots"))
                    .font(.headline)
                Spacer()
                Text(L("Drag order is represented by the arrow buttons."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                if let locale {
                    ForEach(visibleSlots) { slot in
                        let assets = state.orderedScreenshotAssets(
                            group?.assets.filter { $0.deviceSlot == slot } ?? [],
                            locale: locale,
                            slot: slot
                        )
                        if !assets.isEmpty || missing.contains(where: { $0.contains(slot) }) {
                            ScreenshotSlotSection(
                                title: slot.displayName,
                                subtitle: slot.requiredCopy,
                                assets: assets,
                                focusedAssetID: state.selectedScreenshotAssetId,
                                assetFocusID: { state.screenshotAssetFocusID($0) }
                            ) { asset, direction in
                                state.moveScreenshotAsset(asset, locale: locale, direction: direction)
                            }
                            .id(state.screenshotSlotFocusID(locale: locale, slot: slot))
                        }
                    }

                    let unsupported = state.orderedScreenshotAssets(
                        group?.assets.filter { $0.deviceSlot == nil } ?? [],
                        locale: locale,
                        slot: nil
                    )
                    if !unsupported.isEmpty {
                        ScreenshotSlotSection(
                            title: L("Unsupported"),
                            subtitle: L("These files will not be ready for App Store Connect until resized."),
                            assets: unsupported,
                            focusedAssetID: state.selectedScreenshotAssetId,
                            assetFocusID: { state.screenshotAssetFocusID($0) }
                        ) { asset, direction in
                            state.moveScreenshotAsset(asset, locale: locale, direction: direction)
                        }
                        .id(state.screenshotSlotFocusID(locale: locale, slot: nil))
                    }
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func remoteScreenshotCountText(for group: ScreenshotLocaleGroup) -> String {
        guard !group.isUnassigned else { return "-" }
        if let count = state.remoteScreenshotCountsByLocale[group.locale] {
            return "\(count)"
        }
        return state.isLoadingRemoteScreenshotCounts ? "…" : "-"
    }
}
