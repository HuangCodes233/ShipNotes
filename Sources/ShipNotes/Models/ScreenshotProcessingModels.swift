import Foundation

/// Keeps the original uploaded IDs so checking Apple's queue never requires
/// deleting the set or uploading the same screenshots a second time.
struct ScreenshotProcessingReservation: Codable, Hashable, Sendable {
    struct UploadedFile: Codable, Hashable, Sendable {
        let id: String
        let fileName: String
    }

    let localizationId: String
    let displayType: String
    let setId: String
    var uploaded: [UploadedFile]
    var failureDetails: [String] = []
}

struct ScreenshotProcessingPendingError: LocalizedError, Sendable {
    let reservation: ScreenshotProcessingReservation

    var errorDescription: String? {
        L(
            "Screenshots uploaded. Apple is still processing them. Check processing status before replacing this set again."
        )
    }
}

struct PendingScreenshotProcessing: Codable, Hashable, Sendable {
    let appId: String
    let versionId: String
    let locale: String
    var reservation: ScreenshotProcessingReservation

    var key: String {
        // Encode the tuple so separators inside IDs cannot collide.
        let components = [appId, versionId, reservation.localizationId, reservation.displayType]
        return (try? JSONEncoder().encode(components)).flatMap { String(data: $0, encoding: .utf8) }
            ?? reservation.setId
    }
}
