import Foundation
import OSLog

// App list, version list, and version creation.
extension AppStoreConnectClient {
    func validateCredentials() async throws {
        _ = try await requestCollection(
            ASCAppResource.self,
            path: "apps",
            queryItems: [
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "fields[apps]", value: "name,bundleId"),
            ],
            paged: false
        )
    }

    func fetchApps() async throws -> [AppRecord] {
        // Note: `sort` is not accepted on every endpoint. We sort client-side instead.
        let resources = try await requestCollection(
            ASCAppResource.self,
            path: "apps",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "fields[apps]", value: "name,bundleId"),
            ]
        )
        let artworkURLs = await fetchArtworkURLs(forAppIds: resources.map(\.id))
        let apps = resources.map { resource in
            AppRecord(
                id: resource.id,
                name: resource.attributes?.name ?? "Untitled App",
                bundleId: resource.attributes?.bundleId ?? "unknown.bundle",
                platform: "App",
                iconSystemName: "app",
                iconURL: artworkURLs[resource.id]
            )
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchVersions(appId: String) async throws -> [ReleaseVersion] {
        // The appStoreVersions collection rejects `sort` (PARAMETER_ERROR.ILLEGAL).
        // Fetch unordered, then sort by versionString descending client-side.
        let resources = try await requestCollection(
            ASCVersionResource.self,
            path: "apps/\(appId)/appStoreVersions",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(
                    name: "fields[appStoreVersions]",
                    value: "platform,versionString,appStoreState,appVersionState,createdDate"),
            ]
        )
        let versions = resources.map { resource in
            let rawState = resource.attributes?.appStoreState ?? resource.attributes?.appVersionState
            return ReleaseVersion(
                id: resource.id,
                appId: appId,
                versionString: resource.attributes?.versionString ?? "Unknown",
                platform: displayPlatform(resource.attributes?.platform),
                appStoreState: AppStoreVersionState(apiValue: rawState),
                createdDate: resource.attributes?.createdDate.flatMap { Self.parseAppStoreConnectDate($0) }
            )
        }
        return versions.sorted { $0.versionString.localizedStandardCompare($1.versionString) == .orderedDescending }
    }

    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion {
        let body = ASCVersionCreateRequest(
            appId: appId,
            versionString: versionString,
            platform: platform
        )
        let response = try await requestResource(
            ASCVersionResource.self,
            path: "appStoreVersions",
            method: "POST",
            body: body
        )
        let rawState = response.attributes?.appStoreState ?? response.attributes?.appVersionState
        return ReleaseVersion(
            id: response.id,
            appId: appId,
            versionString: response.attributes?.versionString ?? versionString,
            platform: displayPlatform(response.attributes?.platform),
            appStoreState: AppStoreVersionState(apiValue: rawState),
            createdDate: response.attributes?.createdDate.flatMap { Self.parseAppStoreConnectDate($0) }
        )
    }

    /// Best-effort icon lookup against the public iTunes endpoint. Icons are
    /// decoration, so every failure (offline, throttled, schema drift) degrades
    /// to "no icons" instead of failing the whole app list.
    func fetchArtworkURLs(forAppIds appIds: [String]) async -> [String: URL] {
        let ids = appIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [:] }

        // The iTunes lookup endpoint rejects queries with too many ids
        // (>~200), so large accounts are looked up in batches.
        let batches = stride(from: 0, to: ids.count, by: Self.artworkLookupBatchSize).map {
            Array(ids[$0..<min($0 + Self.artworkLookupBatchSize, ids.count)])
        }

        var merged: [String: URL] = [:]
        for batch in batches {
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
            components?.queryItems = [
                URLQueryItem(name: "id", value: batch.joined(separator: ",")),
                URLQueryItem(name: "entity", value: "software"),
            ]
            guard let url = components?.url else { continue }

            do {
                let request = URLRequest(url: url)
                let (data, response) = try await performDataRequest(request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw AppStoreConnectClientError.invalidResponse
                }
                let lookup = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
                for result in lookup.results {
                    guard let trackId = result.trackId,
                        let artwork = result.bestArtworkURL
                    else { continue }
                    merged[String(trackId)] = artwork
                }
            } catch {
                Logger.network.error("Error fetching artwork URLs: \(error.localizedDescription)")
                // Best-effort: keep whatever earlier batches resolved.
            }
        }
        return merged
    }

    static let artworkLookupBatchSize = 200
}

private struct ITunesLookupResponse: Decodable {
    var results: [ITunesSoftwareResult]
}

private struct ITunesSoftwareResult: Decodable {
    var trackId: Int?
    var artworkUrl512: String?
    var artworkUrl100: String?
    var artworkUrl60: String?

    var bestArtworkURL: URL? {
        [artworkUrl512, artworkUrl100, artworkUrl60]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}
