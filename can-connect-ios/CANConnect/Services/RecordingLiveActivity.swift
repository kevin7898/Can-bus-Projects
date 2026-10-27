@preconcurrency import ActivityKit
import UIKit
import OSLog

struct RecordingActivitySnapshot: Equatable {
    var id: UUID
    var source: String
    var countUnit: String
    var state: RecordingActivityAttributes.ContentState
    init(draft: RecordingDraft, scannerConnected: Bool) {
        id = draft.id
        switch draft.source {
        case .scanner: source = draft.scannerTransport?.shortTitle ?? "Scanner"
        case .phoneGPS: source = "Phone GPS"
        case .demo: source = "Sample recording"
        default: source = "Recording"
        }
        countUnit = draft.source == .phoneGPS ? "GPS points" : draft.source == .demo ? "" : "responses"
        state = .init(startedAt:draft.startedAt,updatedAt:draft.source == .scanner ? draft.updatedAt : Date(),
                      responses:draft.source == .phoneGPS ? draft.route.count : max(draft.liveEvidence.sampleCount,draft.samples?.count ?? 0),
                      status:draft.source == .scanner && !scannerConnected ? "Scanner disconnected" : "Recording")
    }
}

@MainActor
protocol RecordingActivityManaging: AnyObject {
    func sync(_ snapshot: RecordingActivitySnapshot?, foreground: Bool)
}

@MainActor
final class RecordingLiveActivity: RecordingActivityManaging {
    private var previous: RecordingActivitySnapshot?
    private var lastUpdate = Date.distantPast
    private var pending: Task<Void,Never>?
    private var requested = Set<UUID>()
    private let enabled: Bool
    init() {
        let process = ProcessInfo.processInfo
        enabled = process.arguments.contains("--live-activity-testing") ||
            (process.environment["XCTestConfigurationFilePath"] == nil && !process.arguments.contains("--ui-testing"))
    }
    func sync(_ snapshot: RecordingActivitySnapshot?, foreground: Bool) {
        guard enabled else { return }
        let date = Date()
        // Coalesce sample updates; the system renders elapsed time without writes
        // every second. Lifecycle transitions and foreground retries are immediate.
        guard snapshot?.id != previous?.id || snapshot?.state.status != previous?.state.status
                || date.timeIntervalSince(lastUpdate) >= 5 || (foreground && snapshot != nil && !requested.contains(snapshot!.id)) else { return }
        let old = previous; previous = snapshot; lastUpdate = date
        let preceding = pending
        pending = Task { [weak self] in
            await preceding?.value
            guard let self else { return }
            await self.apply(snapshot, previous:old, foreground:foreground)
        }
    }
    private func apply(_ snapshot: RecordingActivitySnapshot?, previous: RecordingActivitySnapshot?, foreground: Bool) async {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.attributes.recordingID != snapshot?.id {
            var state = activity.content.state
            if activity.attributes.recordingID == previous?.id, let previous { state = previous.state }
            state.ended = true
            // On relaunch the app recovered the checkpoint; never leave a stale
            // "Recording" badge claiming acquisition is still running.
            state.status = previous == nil ? "Recording recovered" : "Recording saved"
            await activity.end(ActivityContent(state:state,staleDate:nil),dismissalPolicy:.immediate)
        }
        guard let snapshot else { return }
        let content = ActivityContent(state:snapshot.state,staleDate:snapshot.state.updatedAt.addingTimeInterval(20))
        if let activity = Activity<RecordingActivityAttributes>.activities.first(where:{$0.attributes.recordingID == snapshot.id}) {
            await activity.update(content)
        } else if foreground, UIApplication.shared.applicationState == .active,
                  !requested.contains(snapshot.id), ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity.request(attributes:RecordingActivityAttributes(recordingID:snapshot.id,source:snapshot.source,countUnit:snapshot.countUnit),content:content,pushType:nil)
                requested.insert(snapshot.id)
            } catch {
                Logger(subsystem:"com.canconnect.companion",category:"LiveActivity").error("Could not start recording activity: \(error.localizedDescription,privacy:.public)")
                // Live Activity availability must never interrupt acquisition or
                // saving. Retry when the app next becomes active.
            }
        }
    }
}
