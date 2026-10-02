import SwiftUI

struct SyncHistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 380, idealHeight: 520)
    }

    private var header: some View {
        HStack {
            Label(L("Sync History"), systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Spacer()
            Button(L("Done")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        } else {
            List {
                ForEach(state.syncHistory) { run in
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
        let appName = apps.first { $0.id == run.appId }?.name ?? run.appId
        let versionString = versionsByApp[run.appId]?.first { $0.id == run.versionId }?.versionString ?? run.versionId
        let prefix = run.dryRun ? L("Dry run") : L("Sync")
        return "\(prefix) · \(appName) \(versionString)"
    }

    private var subtitle: String {
        let succeeded = run.localeResults.values.filter { if case .succeeded = $0 { true } else { false } }.count
        let failed = run.localeResults.values.filter { if case .failed = $0 { true } else { false } }.count
        let skipped = run.localeResults.values.filter { if case .skipped = $0 { true } else { false } }.count
        var parts: [String] = []
        if succeeded > 0 { parts.append(L("%d succeeded", succeeded)) }
        if failed > 0 { parts.append(L("%d failed", failed)) }
        if skipped > 0 { parts.append(L("%d skipped", skipped)) }
        return parts.joined(separator: " · ")
    }

    private var iconColor: Color {
        switch run.result {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
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
        }
    }
}
