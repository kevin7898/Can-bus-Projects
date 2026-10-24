import ActivityKit
import Foundation

// No VIN, route, server address or other private vehicle data leaves the app.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var updatedAt: Date
        var responses: Int
        var status: String
        var ended: Bool = false
        var elapsedText: String {
            let seconds = max(0, Int(updatedAt.timeIntervalSince(startedAt)))
            return seconds >= 3600 ? String(format:"%d:%02d:%02d",seconds/3600,(seconds%3600)/60,seconds%60)
                : String(format:"%02d:%02d",seconds/60,seconds%60)
        }
    }
    var recordingID: UUID
    var source: String
    var countUnit: String
}
