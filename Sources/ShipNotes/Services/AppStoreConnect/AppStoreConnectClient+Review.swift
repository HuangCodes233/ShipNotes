import Foundation
import OSLog

// Review submission create / attach / submit.
extension AppStoreConnectClient {
    /// Review submissions that can still take items and be submitted: one that
    /// was created but never submitted, and one Apple sent back with issues.
    /// Submissions already waiting for or in review can't be changed, so
    /// "reusing" one would report success without submitting this version.
    static let reusableReviewSubmissionStates = ["READY_FOR_REVIEW", "UNRESOLVED_ISSUES"]

    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String {
        // Step 1: open a review submission for the app on this platform. A
        // leftover open submission from an earlier interrupted attempt makes
        // Apple reject a new one with 409 — recover that existing submission.
        // App Store Connect also uses 409 for ordinary validation failures, so
        // any other 409 is rethrown with Apple's own message.
        let createBody = ASCReviewSubmissionCreateRequest(appId: appId, platform: platform)
        let submission: ASCReviewSubmissionResource
        do {
            submission = try await requestResource(
                ASCReviewSubmissionResource.self,
                path: "reviewSubmissions",
                method: "POST",
                body: createBody
            )
        } catch let error as AppStoreConnectClientError {
            guard case .requestFailed(statusCode: 409, _) = error,
                  let existing = try? await reusableOpenSubmission(appId: appId, platform: platform) else {
                throw error
            }
            Logger.network.info("Reusing open review submission after 409.")
            submission = existing
        }
        return try await attachAndSubmit(submission: submission, versionId: versionId)
    }

    /// The open submission to recover after a 409, preferring the unsubmitted
    /// draft an interrupted attempt leaves behind over a rejected submission.
    private func reusableOpenSubmission(
        appId: String,
        platform: String
    ) async throws -> ASCReviewSubmissionResource? {
        let submissions = try await requestCollection(
            ASCReviewSubmissionResource.self,
            path: "reviewSubmissions",
            queryItems: [
                URLQueryItem(name: "filter[app]", value: appId),
                URLQueryItem(name: "filter[platform]", value: platform),
                URLQueryItem(name: "filter[state]", value: Self.reusableReviewSubmissionStates.joined(separator: ",")),
                URLQueryItem(name: "fields[reviewSubmissions]", value: "state,platform,submittedDate"),
                URLQueryItem(name: "limit", value: "20")
            ],
            paged: false
        )
        // Filter again locally: the answer decides where this version goes.
        let candidates = submissions.filter { resource in
            guard let state = resource.attributes?.state,
                  Self.reusableReviewSubmissionStates.contains(state) else { return false }
            return resource.attributes?.platform == nil || resource.attributes?.platform == platform
        }
        for state in Self.reusableReviewSubmissionStates {
            if let match = candidates.first(where: { $0.attributes?.state == state }) {
                return match
            }
        }
        return nil
    }

    /// Attach the App Store version as a reviewable item and flip
    /// `submitted` to true. Shared by the fresh-create and 409-recovery paths.
    private func attachAndSubmit(
        submission: ASCReviewSubmissionResource,
        versionId: String
    ) async throws -> String {
        let submissionId = submission.id

        // Step 2: attach the App Store version as a reviewable item. A 409 is
        // fine only when a previous attempt already attached this version;
        // otherwise it is Apple rejecting the version (missing build,
        // screenshots, …) and that message has to reach the user.
        let itemBody = ASCReviewSubmissionItemCreateRequest(submissionId: submissionId, versionId: versionId)
        do {
            _ = try await requestResource(
                ASCReviewSubmissionItemResource.self,
                path: "reviewSubmissionItems",
                method: "POST",
                body: itemBody
            )
        } catch let error as AppStoreConnectClientError {
            guard case .requestFailed(statusCode: 409, _) = error,
                  (try? await reviewSubmission(submissionId, containsVersion: versionId)) == true else {
                throw error
            }
            Logger.network.info("Review submission item already attached (409); continuing to submit.")
        }

        // Step 3: flip `submitted` to true to actually submit to Apple.
        let submitBody = ASCReviewSubmissionUpdateRequest(submissionId: submissionId)
        let final = try await requestResource(
            ASCReviewSubmissionResource.self,
            path: "reviewSubmissions/\(submissionId)",
            method: "PATCH",
            body: submitBody
        )
        return final.attributes?.state ?? "SUBMITTED"
    }

    private func reviewSubmission(_ submissionId: String, containsVersion versionId: String) async throws -> Bool {
        let items = try await requestCollection(
            ASCReviewSubmissionItemResource.self,
            path: "reviewSubmissions/\(submissionId)/items",
            queryItems: [
                URLQueryItem(name: "include", value: "appStoreVersion"),
                URLQueryItem(name: "limit", value: "50")
            ]
        )
        return items.contains { $0.relationships?.appStoreVersion?.data?.id == versionId }
    }
}
