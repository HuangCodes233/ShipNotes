import Foundation

@MainActor
extension AppState {
    /// The submit request has crossed its last content check. UI controls in
    /// every window are disabled, and model entry points also protect against
    /// shortcuts, file watchers and asynchronous parser/AI completions.
    func allowWorkspaceMutation() -> Bool {
        guard !isFinalizingReviewSubmission else {
            reviewBlockedWorkspaceChange = true
            return false
        }
        return true
    }
}
