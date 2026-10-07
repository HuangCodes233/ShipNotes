import Foundation

@MainActor
extension AppState {
    func recordSyncRun(
        localeResults: [String: LocaleSyncResult],
        dryRun: Bool,
        kind: SyncKind = .releaseNotes,
        appId: String? = nil,
        versionId: String? = nil
    ) {
        let run = SyncRun(
            id: UUID(),
            appId: appId ?? selectedAppId ?? "",
            versionId: versionId ?? selectedVersionId ?? "",
            startedAt: Date(),
            completedAt: Date(),
            dryRun: dryRun,
            localeResults: localeResults,
            kind: kind,
            appName: apps.first { $0.id == (appId ?? selectedAppId) }?.name,
            versionString: versionsByApp[appId ?? selectedAppId ?? ""]?
                .first { $0.id == (versionId ?? selectedVersionId) }?.versionString
        )
        appendSyncRun(run)
    }

    internal static let syncHistoryPersistKey = "shipnotes.syncHistory.v1"
    internal static let syncHistoryMaxRetained = 100

    /// Insert a run at the head, cap the list at `syncHistoryMaxRetained`,
    /// and write the result to UserDefaults so it survives an app relaunch.
    func appendSyncRun(_ run: SyncRun) {
        syncHistory.insert(run, at: 0)
        if syncHistory.count > Self.syncHistoryMaxRetained {
            syncHistory = Array(syncHistory.prefix(Self.syncHistoryMaxRetained))
        }
        persistSyncHistory()
    }

    func persistSyncHistory() {
        do {
            let encoder = JSONEncoder()
            // Use ISO 8601 so timestamps are stable, human-readable, and not
            // dependent on the encoder's default (deferred-to-date) strategy.
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(syncHistory)
            defaults.set(data, forKey: Self.syncHistoryPersistKey)
        } catch {
            // Persistence is best-effort; don't surface this to the user.
            // The next run will retry.
        }
    }

    /// Restore previously-persisted sync runs into the in-memory history.
    /// Called from init so the user sees their past runs immediately on launch.
    func loadPersistedSyncHistory() {
        guard let data = defaults.data(forKey: Self.syncHistoryPersistKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Fall back to the default (deferred-to-date) strategy if the payload
        // was written by an older build that didn't use ISO 8601 yet.
        let runs =
            (try? decoder.decode([SyncRun].self, from: data))
            ?? (try? JSONDecoder().decode([SyncRun].self, from: data))
        guard let runs else { return }
        syncHistory = runs
    }
}
