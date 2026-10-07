import SwiftUI

struct SyncHistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var query = SyncHistoryQuery()

    private var filteredRuns: [SyncRun] {
        query.filter(state.syncHistory, apps: state.apps, versions: state.versionsByApp)
    }

    private var appOptions: [(id: String, name: String)] {
        let names = state.syncHistory.reduce(into: [String: String]()) { names, run in
            names[run.appId] = run.displayAppName(apps: state.apps)
        }
        return names.map { (id: $0.key, name: $0.value) }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            content
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 440, idealHeight: 560)
    }

    private var header: some View {
        HStack {
            Label(L("Sync History"), systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Spacer()
            Menu(L("Export…")) {
                Button(L("Export JSON…")) { export(.json) }
                Button(L("Export CSV…")) { export(.csv) }
            }
            .disabled(filteredRuns.isEmpty)
            Button(L("Done")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Search app, version, or locale"), text: $query.search)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker(L("App"), selection: $query.appId) {
                    Text(L("All apps")).tag("")
                    ForEach(appOptions, id: \.id) { app in Text(app.name).tag(app.id) }
                }
                Picker(L("Operation"), selection: $query.kind) {
                    Text(L("All operations")).tag("")
                    Text(L("Release Notes")).tag(SyncKind.releaseNotes.rawValue)
                    Text(L("Store Copy")).tag(SyncKind.storeCopy.rawValue)
                    Text(L("Screenshots")).tag(SyncKind.screenshots.rawValue)
                }
                Picker(L("Result"), selection: $query.outcome) {
                    ForEach(SyncHistoryOutcome.allCases) { outcome in Text(outcome.title).tag(outcome) }
                }
            }
            Text(L("Showing %1$d of %2$d runs", filteredRuns.count, state.syncHistory.count))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func export(_ format: SyncHistoryExportFormat) {
        do {
            let data = try SyncHistoryExport.data(
                for: filteredRuns, format: format, apps: state.apps, versions: state.versionsByApp
            )
            SyncHistoryExporter.present(data: data, format: format) { state.handleError($0) }
        } catch { state.handleError(error) }
    }

    @ViewBuilder
    private var content: some View {
        if state.syncHistory.isEmpty {
            ContentUnavailableView {
                Label(L("No sync runs yet"), systemImage: "tray")
            } description: {
                Text(L("Dry runs and real syncs will appear here once you publish or preview a release."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRuns.isEmpty {
            ContentUnavailableView(L("No matching runs"), systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredRuns) { run in
                    SyncRunRow(run: run, apps: state.apps, versionsByApp: state.versionsByApp)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct SyncRunRow: View {
    let run: SyncRun
    let apps: [AppRecord]
    let versionsByApp: [String: [ReleaseVersion]]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(run.localeResults.keys.sorted(), id: \.self) { locale in
                    HStack(spacing: 8) {
                        Text(locale)
                            .font(.callout.monospaced())
                            .frame(width: 90, alignment: .leading)
                        resultBadge(run.localeResults[locale] ?? .skipped)
                        if case .failed(let msg) = run.localeResults[locale] ?? .skipped {
                            Text(msg).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: run.dryRun ? "play.slash" : kindIcon)
                    .foregroundStyle(run.dryRun ? Color.secondary : iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.body)
                        kindChip
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(run.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var kindChip: some View {
        Text(run.resolvedKind.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private var kindIcon: String {
        switch run.resolvedKind {
        case .releaseNotes: "checkmark.icloud.fill"
        case .storeCopy: "text.quote"
        case .screenshots: "photo.fill"
        }
    }

    private var title: String {
        let appName = run.displayAppName(apps: apps)
        let versionString = run.displayVersion(versions: versionsByApp)
        let prefix = run.dryRun ? L("Dry run") : L("Sync")
        return "\(prefix) · \(appName) \(versionString)"
    }

    private var subtitle: String {
        let succeeded = run.localeResults.values.filter { if case .succeeded = $0 { true } else { false } }.count
        let failed = run.localeResults.values.filter { if case .failed = $0 { true } else { false } }.count
        let skipped = run.localeResults.values.filter { if case .skipped = $0 { true } else { false } }.count
        let processing = run.localeResults.values.filter { if case .processing = $0 { true } else { false } }.count
        var parts: [String] = []
        if succeeded > 0 { parts.append(L("%d succeeded", succeeded)) }
        if failed > 0 { parts.append(L("%d failed", failed)) }
        if skipped > 0 { parts.append(L("%d skipped", skipped)) }
        if processing > 0 { parts.append(L("%d processing", processing)) }
        return parts.joined(separator: " · ")
    }

    private var iconColor: Color {
        switch run.result {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
        case .processing: .orange
        }
    }

    @ViewBuilder
    private func resultBadge(_ result: LocaleSyncResult) -> some View {
        switch result {
        case .succeeded:
            Label(L("Succeeded"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Label(L("Failed"), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .skipped:
            Label(L("Skipped"), systemImage: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .processing:
            Label(L("Processing"), systemImage: "clock")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }
}
