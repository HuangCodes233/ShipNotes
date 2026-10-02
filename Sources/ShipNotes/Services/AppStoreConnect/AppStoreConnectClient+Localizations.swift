import Foundation
import OSLog

// whatsNew, store metadata, and localization create/fetch.
extension AppStoreConnectClient {
    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote] {
        let resources = try await requestCollection(
            ASCLocalizationResource.self,
            path: "appStoreVersions/\(versionId)/appStoreVersionLocalizations",
            queryItems: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(
                    name: "fields[appStoreVersionLocalizations]",
                    value: "locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew"
                )
            ]
        )
        return resources.compactMap(remoteLocaleNote)
    }

    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote {
        let body = ASCLocalizationUpdateRequest(id: localizationId, whatsNew: text)
        let response = try await requestResource(
            ASCLocalizationResource.self,
            path: "appStoreVersionLocalizations/\(localizationId)",
            method: "PATCH",
            body: body
        )
        guard let note = remoteLocaleNote(from: response) else {
            throw AppStoreConnectClientError.invalidResponse
        }
        return note
    }

    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote {
        let body = ASCLocalizationUpdateRequest(id: localizationId, metadata: metadata)
        let response = try await requestResource(
            ASCLocalizationResource.self,
            path: "appStoreVersionLocalizations/\(localizationId)",
            method: "PATCH",
            body: body
        )
        guard let note = remoteLocaleNote(from: response) else {
            throw AppStoreConnectClientError.invalidResponse
        }
        return note
    }

    func updateStoreMetadataField(localizationId: String, field: StoreCopyField, value: String) async throws -> RemoteLocaleNote {
        let body = ASCLocalizationUpdateRequest(id: localizationId, field: field, value: value)
        let response = try await requestResource(
            ASCLocalizationResource.self,
            path: "appStoreVersionLocalizations/\(localizationId)",
            method: "PATCH",
            body: body
        )
        guard let note = remoteLocaleNote(from: response) else {
            throw AppStoreConnectClientError.invalidResponse
        }
        return note
    }

    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote {
        let body = ASCLocalizationCreateRequest(versionId: versionId, locale: locale, whatsNew: text)
        let response = try await requestResource(
            ASCLocalizationResource.self,
            path: "appStoreVersionLocalizations",
            method: "POST",
            body: body
        )
        guard let note = remoteLocaleNote(from: response) else {
            throw AppStoreConnectClientError.invalidResponse
        }
        return note
    }

    func remoteLocaleNote(from resource: ASCLocalizationResource) -> RemoteLocaleNote? {
        guard let locale = resource.attributes?.locale else { return nil }
        return RemoteLocaleNote(
            localizationId: resource.id,
            locale: locale,
            text: resource.attributes?.whatsNew ?? "",
            storeMetadata: StoreMetadataFields(
                description: resource.attributes?.description ?? "",
                keywords: resource.attributes?.keywords ?? "",
                promotionalText: resource.attributes?.promotionalText ?? "",
                supportURL: resource.attributes?.supportUrl ?? "",
                marketingURL: resource.attributes?.marketingUrl ?? "",
                privacyPolicyURL: ""
            )
        )
    }
}
