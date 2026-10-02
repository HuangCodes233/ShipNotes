import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// Field editors, split divider, and compare panel live in
// StoreCopyWorkspaceComponents.swift.

struct StoreCopyWorkspaceView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder = [KeyPathComparator(\StoreCopyLocale.locale)]
    @State private var comparedStoreCopyField: StoreCopyField?
    @State private var showNewVersionSheet = false
    @State private var isDropTargeted = false
    @SceneStorage("storeCopy.localePaneWidth") private var localePaneWidth = 380.0
    @GestureState private var localePaneDragOffset: CGFloat = 0

    private let pageHorizontalPadding: CGFloat = 32
    private let pageVerticalPadding: CGFloat = 24
    private let minimumLocalePaneWidth: CGFloat = 320
    private let maximumLocalePaneWidth: CGFloat = 560
    private let minimumEditorPaneWidth: CGFloat = 380
    private let splitDividerHitWidth: CGFloat = 12

    var body: some View {
        if state.selectedAppId == nil {
            SelectAppEmptyState(description: L("Choose an app from the sidebar to manage its store copy."))
        } else {
            mainWorkspace
        }
    }

    private var mainWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            versionRow
            summaryRow

            resizableEditor
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.vertical, pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.loadStoreCopySource(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropZoneOverlay(isTargeted: isDropTargeted)
        .onChange(of: state.selectedStoreCopyLocale) { _, _ in
            comparedStoreCopyField = nil
        }
        .sheet(isPresented: $showNewVersionSheet) {
            NewVersionSheet(
                defaultPlatform: NewVersionSheet.defaultPlatform(
                    selectedVersion: state.selectedVersion,
                    selectedAppId: state.selectedAppId,
                    versionsByApp: state.versionsByApp
                ),
                suggestedVersion: NewVersionSheet.suggestedNextVersion(
                    selectedVersion: state.selectedVersion,
                    selectedAppId: state.selectedAppId,
                    versionsByApp: state.versionsByApp
                )
            )
            .environment(state)
        }
    }

    private var resizableEditor: some View {
        GeometryReader { geometry in
            let maximumAvailableWidth = max(
                minimumLocalePaneWidth,
                min(
                    maximumLocalePaneWidth,
                    geometry.size.width - minimumEditorPaneWidth - splitDividerHitWidth
                )
            )
            let effectiveLocalePaneWidth = min(
                max(CGFloat(localePaneWidth) + localePaneDragOffset, minimumLocalePaneWidth),
                maximumAvailableWidth
            )

            HStack(spacing: 0) {
                localeTable
                    .frame(width: effectiveLocalePaneWidth)
                    .frame(maxHeight: .infinity)

                PaneSplitDivider(resizeDescription: L("Resize locale list"))
                    .frame(width: splitDividerHitWidth)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($localePaneDragOffset) { value, offset, _ in
                                offset = value.translation.width
                            }
                            .onEnded { value in
                                let proposedWidth = CGFloat(localePaneWidth) + value.translation.width
                                localePaneWidth = Double(
                                    min(
                                        max(proposedWidth, minimumLocalePaneWidth),
                                        maximumAvailableWidth
                                    )
                                )
                            }
                    )

                editorPane
                    .frame(minWidth: minimumEditorPaneWidth, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(app: state.selectedApp, size: 52, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Store Copy"))
                    .font(.title2.bold())
                Text(state.selectedApp?.name ?? L("No app selected"))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.selectedApp?.bundleId ?? "-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let selected = state.selectedStoreCopy {
                StatusBadge(status: selected.status)
            }
        }
    }

    private var versionRow: some View {
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                versionControls()
                Spacer(minLength: 16)
                storeCopyActions
            }

            VStack(alignment: .leading, spacing: 10) {
                versionControls()
                storeCopyActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versionControls() -> some View {
        VersionPickerRow(showNewVersionSheet: $showNewVersionSheet)
    }

    private var storeCopyActions: some View {
        HStack(spacing: 8) {
            Button {
                state.presentStoreCopyImportPicker()
            } label: {
                Label(L("Import Store Copy"), systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
            .secondaryGlassButton()
            .help(L("Import store copy from a local Markdown, YAML, JSON, text file, or metadata folder (⌘⇧O)."))

            Button {
                state.askAIToReparseCurrentStoreCopy()
            } label: {
                Label(L("AI Re-parse"), systemImage: "sparkles")
            }
            .controlSize(.small)
            .secondaryGlassButton()
            .disabled(!state.canReparseCurrentStoreCopyWithAI)
            .help(state.storeCopyAIReparseHelp + " (⌘⇧R)")

            Button {
                if let locale = state.selectedStoreCopyLocale {
                    state.optimizeStoreCopyLocale(locale)
                }
            } label: {
                Label(L("AI Optimize"), systemImage: "wand.and.stars")
            }
            .controlSize(.small)
            .secondaryGlassButton()
            .disabled(!state.isAIConfigured || state.isAIRunning || state.selectedStoreCopy == nil)
            .help(state.isAIConfigured ? L("Optimize the selected locale's store copy with AI.") : L("Configure AI in Settings first."))

            Button {
                if let locale = state.selectedStoreCopyLocale {
                    state.syncStoreCopyLocale(locale)
                }
            } label: {
                Label(L("Sync Current Language"), systemImage: "icloud.and.arrow.up")
            }
            .controlSize(.small)
            .primarySyncButton()
            .disabled(!state.canSyncSelectedStoreCopy)
            .help(L("Upload the selected locale's store copy to App Store Connect."))

            Button {
                state.syncAllStoreCopy()
            } label: {
                Label(L("Sync All"), systemImage: "icloud.and.arrow.up.fill")
            }
            .controlSize(.small)
            .secondaryGlassButton()
            .disabled(!state.canSyncAllStoreCopy)
            .help(L("Upload every changed store-copy locale to App Store Connect."))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var summaryRow: some View {
        let stats = state.storeCopyStats
        return HStack(spacing: 10) {
            summaryPill(title: L("Locales"), value: "\(state.storeCopyLocales.count)", color: .secondary)
            summaryPill(title: L("Ready"), value: "\(stats.readyCount)", color: .green)
            summaryPill(title: L("Pending"), value: "\(stats.pendingSyncCount)", color: .orange)
            summaryPill(title: L("Issues"), value: "\(stats.issueCount)", color: stats.issueCount == 0 ? .green : .red)
            if let source = state.storeCopySourceDescription {
                Text(source)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private var localeTable: some View {
        @Bindable var state = state
        return Table(state.storeCopyLocales.sorted(using: sortOrder), selection: Binding<String?>(
            get: { state.selectedStoreCopyLocale },
            set: { if let code = $0 { state.selectStoreCopyLocale(code) } }
        ), sortOrder: $sortOrder) {
            TableColumn(L("Locale"), value: \.locale) { copy in
                Text(copy.locale)
                    .font(.callout.monospaced())
            }
            .width(min: 70, ideal: 90)

            TableColumn(L("Status"), value: \.status) { copy in
                StatusBadge(status: copy.status)
            }
            .width(min: 96, ideal: 120)

            TableColumn(L("Changed")) { copy in
                Text(copy.changedFieldCount == 0 ? "—" : "\(copy.changedFieldCount)")
                    .foregroundStyle(copy.changedFieldCount == 0 ? Color.secondary : Color.orange)
                    .monospacedDigit()
            }
            .width(min: 56, ideal: 70)

            TableColumn(L("Issues")) { copy in
                if copy.issueCount == 0 {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Label("\(copy.issueCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                }
            }
            .width(min: 56, ideal: 70)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private var editorPane: some View {
        if let copy = state.selectedStoreCopy {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text(copy.locale)
                            .font(.headline.monospaced())
                        StatusBadge(status: copy.status)
                        Spacer()
                        Button {
                            state.revertStoreCopyToRemote(copy.locale)
                        } label: {
                            Label(L("Revert"), systemImage: "arrow.uturn.backward")
                        }
                        .controlSize(.small)
                        .disabled(copy.remoteMetadata == nil || copy.changedFieldCount == 0)
                        .help(L("Restore this locale's store copy from App Store Connect."))
                    }

                    // Group 1: 📝 Description & Promotional Text
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("Marketing & Description"), systemImage: "text.alignleft")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StoreCopyTextBlock(
                            field: .subtitle,
                            text: fieldBinding(copy: copy, field: .subtitle),
                            issues: issues(for: .subtitle, in: copy),
                            minHeight: 48,
                            remoteText: remoteValue(for: .subtitle, in: copy),
                            isComparing: comparedStoreCopyField == .subtitle,
                            canSyncField: canSyncField(.subtitle, in: copy),
                            onToggleCompare: { toggleComparedField(.subtitle) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .subtitle) }
                        )
                        if comparedStoreCopyField == .subtitle {
                            comparePanel(for: .subtitle, in: copy)
                        }

                        StoreCopyTextBlock(
                            field: .description,
                            text: fieldBinding(copy: copy, field: .description),
                            issues: issues(for: .description, in: copy),
                            minHeight: 180,
                            remoteText: remoteValue(for: .description, in: copy),
                            isComparing: comparedStoreCopyField == .description,
                            canSyncField: canSyncField(.description, in: copy),
                            onToggleCompare: { toggleComparedField(.description) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .description) }
                        )
                        if comparedStoreCopyField == .description {
                            comparePanel(for: .description, in: copy)
                        }

                        StoreCopyTextBlock(
                            field: .promotionalText,
                            text: fieldBinding(copy: copy, field: .promotionalText),
                            issues: issues(for: .promotionalText, in: copy),
                            minHeight: 72,
                            remoteText: remoteValue(for: .promotionalText, in: copy),
                            isComparing: comparedStoreCopyField == .promotionalText,
                            canSyncField: canSyncField(.promotionalText, in: copy),
                            onToggleCompare: { toggleComparedField(.promotionalText) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .promotionalText) }
                        )
                        if comparedStoreCopyField == .promotionalText {
                            comparePanel(for: .promotionalText, in: copy)
                        }
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))

                    // Group 2: 🔑 Keywords Section with Interactive Tags
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("Search Keywords"), systemImage: "key.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StoreCopyTextBlock(
                            field: .keywords,
                            text: fieldBinding(copy: copy, field: .keywords),
                            issues: issues(for: .keywords, in: copy),
                            minHeight: 60,
                            remoteText: remoteValue(for: .keywords, in: copy),
                            isComparing: comparedStoreCopyField == .keywords,
                            canSyncField: canSyncField(.keywords, in: copy),
                            onToggleCompare: { toggleComparedField(.keywords) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .keywords) }
                        )
                        if comparedStoreCopyField == .keywords {
                            comparePanel(for: .keywords, in: copy)
                        }

                        KeywordsTagView(keywordsText: fieldBinding(copy: copy, field: .keywords))
                            .padding(.top, 4)
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))

                    // Group 3: 🔗 Support & Marketing URLs
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("URLs & Support Links"), systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StoreCopyURLField(
                            field: .supportURL,
                            text: fieldBinding(copy: copy, field: .supportURL),
                            issues: issues(for: .supportURL, in: copy),
                            remoteText: remoteValue(for: .supportURL, in: copy),
                            isComparing: comparedStoreCopyField == .supportURL,
                            canSyncField: canSyncField(.supportURL, in: copy),
                            onToggleCompare: { toggleComparedField(.supportURL) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .supportURL) }
                        )
                        if comparedStoreCopyField == .supportURL {
                            comparePanel(for: .supportURL, in: copy)
                        }

                        StoreCopyURLField(
                            field: .marketingURL,
                            text: fieldBinding(copy: copy, field: .marketingURL),
                            issues: issues(for: .marketingURL, in: copy),
                            remoteText: remoteValue(for: .marketingURL, in: copy),
                            isComparing: comparedStoreCopyField == .marketingURL,
                            canSyncField: canSyncField(.marketingURL, in: copy),
                            onToggleCompare: { toggleComparedField(.marketingURL) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .marketingURL) }
                        )
                        if comparedStoreCopyField == .marketingURL {
                            comparePanel(for: .marketingURL, in: copy)
                        }

                        StoreCopyURLField(
                            field: .privacyPolicyURL,
                            text: fieldBinding(copy: copy, field: .privacyPolicyURL),
                            issues: issues(for: .privacyPolicyURL, in: copy),
                            remoteText: remoteValue(for: .privacyPolicyURL, in: copy),
                            isComparing: comparedStoreCopyField == .privacyPolicyURL,
                            canSyncField: canSyncField(.privacyPolicyURL, in: copy),
                            onToggleCompare: { toggleComparedField(.privacyPolicyURL) },
                            onSyncField: { state.syncStoreCopyField(locale: copy.locale, field: .privacyPolicyURL) }
                        )
                        if comparedStoreCopyField == .privacyPolicyURL {
                            comparePanel(for: .privacyPolicyURL, in: copy)
                        }
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
                }
                .padding(.trailing, 14)
            }
        } else {
            ContentUnavailableView {
                Label(L("No Store Copy Selected"), systemImage: "text.quote")
            } description: {
                Text(L("Select a locale from the left table to edit App Store description, keywords, and promotional URLs."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func issues(for field: StoreCopyField, in copy: StoreCopyLocale) -> [StoreCopyIssue] {
        copy.validationIssues.filter { $0.field == field }
    }

    private func remoteValue(for field: StoreCopyField, in copy: StoreCopyLocale) -> String? {
        copy.remoteMetadata?.value(for: field)
    }

    private func canSyncField(_ field: StoreCopyField, in copy: StoreCopyLocale) -> Bool {
        guard field.isVersionLocalizationField, !state.isSyncing, state.selectedVersion?.canEditMetadata == true else { return false }
        let localValue = copy.localMetadata.value(for: field)
        let remoteValue = copy.remoteMetadata?.value(for: field) ?? ""
        guard localValue != remoteValue else { return false }
        return !issues(for: field, in: copy).contains { $0.severity == .error }
    }

    private func toggleComparedField(_ field: StoreCopyField) {
        comparedStoreCopyField = comparedStoreCopyField == field ? nil : field
    }

    private func comparePanel(for field: StoreCopyField, in copy: StoreCopyLocale) -> some View {
        StoreCopyComparePanel(
            field: field,
            localText: copy.localMetadata.value(for: field),
            remoteText: remoteValue(for: field, in: copy)
        )
    }

    private func fieldBinding(copy: StoreCopyLocale, field: StoreCopyField) -> Binding<String> {
        Binding(
            get: {
                copy.localMetadata.value(for: field)
            },
            set: { state.updateStoreCopyField(for: copy.locale, field: field, text: $0) }
        )
    }
}
