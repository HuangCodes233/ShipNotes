import Foundation
import Testing
@testable import ShipNotes

@Suite("App Store date parsing")
struct AppStoreConnectDateParsingTests {
    private static let timestamps = [
        "2026-05-19T18:01:23Z", "2026-05-19T18:01:23.456Z",
        "2026-05-19T18:01:23+00:00", "2026-05-19T18:01:23.456+00:00",
        "2026-05-20T03:01:23+09:00", "2026-05-19T11:01:23.456-07:00",
    ]

    private static func expectedDate(for timestamp: String) -> Date {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 5, day: 19, hour: 18, minute: 1, second: 23)
        return components.date!.addingTimeInterval(timestamp.contains(".456") ? 0.456 : 0)
    }

    @Test(arguments: timestamps)
    func acceptsTimestampVariants(_ timestamp: String) throws {
        let date = try #require(AppStoreConnectClient.parseAppStoreConnectDate(timestamp))
        #expect(abs(date.timeIntervalSince(Self.expectedDate(for: timestamp))) < 0.001)
    }

    @Test(arguments: ["", "not a timestamp", "2026-05-19", "18:01:23Z"])
    func rejectsInvalidTimestamps(_ timestamp: String) {
        #expect(AppStoreConnectClient.parseAppStoreConnectDate(timestamp) == nil)
    }

    @Test func parsesConcurrentResponsesWithoutMixingFormats() async {
        let success = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for worker in 0..<12 {
                group.addTask {
                    for index in 0..<100 {
                        let timestamp = Self.timestamps[(index + worker) % Self.timestamps.count]
                        guard let date = AppStoreConnectClient.parseAppStoreConnectDate(timestamp),
                            abs(date.timeIntervalSince(Self.expectedDate(for: timestamp))) < 0.001
                        else {
                            return false
                        }
                    }
                    return true
                }
            }
            var success = true
            for await result in group { success = success && result }
            return success
        }
        #expect(success)
    }
}
