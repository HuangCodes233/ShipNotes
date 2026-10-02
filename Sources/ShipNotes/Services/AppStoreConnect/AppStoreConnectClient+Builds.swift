import Foundation
import OSLog

// Uploaded builds and attaching a build to a version.
extension AppStoreConnectClient {
    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build] {
        let resources = try await requestCollection(
            ASCBuildResource.self,
            path: "builds",
            queryItems: [
                URLQueryItem(name: "filter[app]", value: appId),
                URLQueryItem(name: "filter[preReleaseVersion.version]", value: marketingVersion),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "fields[builds]", value: "version,uploadedDate,expirationDate,processingState")
            ]
        )
        let builds = resources.map { Self.buildFromResource($0, marketingVersion: marketingVersion) }
        return builds.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
    }

    func fetchAllBuilds(appId: String) async throws -> [Build] {
        var url = try makeURL(path: "builds", queryItems: [
            URLQueryItem(name: "filter[app]", value: appId),
            URLQueryItem(name: "include", value: "preReleaseVersion"),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort", value: "-uploadedDate"),
            URLQueryItem(name: "fields[builds]", value: "version,uploadedDate,expirationDate,processingState,preReleaseVersion"),
            URLQueryItem(name: "fields[preReleaseVersions]", value: "version,platform")
        ])
        var builds: [Build] = []
        var pageCount = 0

        while true {
            let request = try await makeRequest(url: url)
            let response = try await send(request, as: ASCBuildCollectionResponse.self)
            let prereleaseVersions = Dictionary(
                uniqueKeysWithValues: (response.included ?? []).map { resource in
                    (resource.id, resource.attributes)
                }
            )

            builds.append(contentsOf: response.data.map { resource in
                let prereleaseID = resource.relationships?.preReleaseVersion?.data?.id
                let prerelease = prereleaseID.flatMap { prereleaseVersions[$0] } ?? nil
                return Self.buildFromResource(
                    resource,
                    marketingVersion: prerelease?.version,
                    platform: prerelease?.platform
                )
            })
            pageCount += 1

            guard pageCount < 20,
                  let next = response.links?.next,
                  let nextURL = URL(string: next) else {
                return builds.sorted {
                    ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast)
                }
            }
            url = nextURL
        }
    }

    func fetchAttachedBuild(versionId: String) async throws -> Build? {
        let url = try makeURL(path: "appStoreVersions/\(versionId)/build", queryItems: [
            URLQueryItem(name: "fields[builds]", value: "version,uploadedDate,expirationDate,processingState")
        ])
        let request = try await makeRequest(url: url)
        do {
            // Apple returns `{"data": null}` for an un-attached version, not 404,
            // so use the nullable response wrapper. 404 fallback stays for safety.
            let response = try await send(request, as: ASCNullableResourceResponse<ASCBuildResource>.self)
            guard let resource = response.data else { return nil }
            return Self.buildFromResource(resource, marketingVersion: nil)
        } catch let AppStoreConnectClientError.requestFailed(statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    func setBuild(_ buildId: String?, forVersion versionId: String) async throws {
        try await patchRelationship(
            path: "appStoreVersions/\(versionId)/relationships/build",
            body: ASCBuildRelationshipUpdate(buildId: buildId)
        )
    }

    func updateVersion(versionId: String, releaseType: String?) async throws {
        let body = ASCVersionUpdateRequest(versionId: versionId, releaseType: releaseType)
        _ = try await requestResource(
            ASCVersionResource.self,
            path: "appStoreVersions/\(versionId)",
            method: "PATCH",
            body: body
        )
    }


    static func buildFromResource(
        _ resource: ASCBuildResource,
        marketingVersion: String?,
        platform: String? = nil
    ) -> Build {
        Build(
            id: resource.id,
            buildNumber: resource.attributes?.version ?? "—",
            marketingVersion: marketingVersion,
            platform: platform,
            uploadedDate: resource.attributes?.uploadedDate,
            expirationDate: resource.attributes?.expirationDate,
            processingState: Build.ProcessingState(apiValue: resource.attributes?.processingState)
        )
    }
}
