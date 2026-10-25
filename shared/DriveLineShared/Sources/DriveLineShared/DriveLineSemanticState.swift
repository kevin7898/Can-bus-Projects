import Foundation

/// User-facing operational states shared by both apps. These words have stable
/// meanings; views must not replace them with vague connected/synced/error text.
public enum DriveLineSemanticState: String, CaseIterable, Identifiable, Sendable, Codable {
    case ready, active, waiting, queued, processing, degraded, stale
    case unavailable, offline, failed, recovered, complete, readOnly = "read-only"

    public var id: String { rawValue }
    public var title: String {
        switch self { case .readOnly: "Read-only"; default: rawValue.capitalized }
    }
    public var icon: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .active: "record.circle.fill"
        case .waiting: "clock"
        case .queued: "arrow.up.circle"
        case .processing: "gearshape.2.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .unavailable: "minus.circle"
        case .offline: "wifi.slash"
        case .failed: "xmark.octagon.fill"
        case .recovered: "arrow.counterclockwise.circle.fill"
        case .complete: "checkmark.seal.fill"
        case .readOnly: "lock.fill"
        }
    }

    // Compatibility aliases while Phase 2-7 call sites adopt precise wording.
    @available(*, deprecated, renamed: "ready") public static var healthy: Self { .ready }
    @available(*, deprecated, renamed: "active") public static var recording: Self { .active }
}

public enum DriveLineStatePlatform: String, CaseIterable, Sendable, Codable {
    case shared, mac, iPhone
}

public enum DriveLineRecoveryAction: String, CaseIterable, Sendable, Codable {
    case configureVehicle, openSettings, retryConnection, continueGPSOnly
    case retrySave, finishRecording, retryTransfer, checkProcessingReceipt
    case chooseCorrectVehicle, restoreBackup, openPreservedOriginal
    case chooseWritableLocation, resumeIngestion, fitAvailableRoute
    case viewCoverageDetails, addFuel, attachReceipt, addRecording
    case configureDestination, reconnectScanner, reviewSuggestion

    public var title: String {
        switch self {
        case .configureVehicle: "Configure vehicle"
        case .openSettings: "Open Settings"
        case .retryConnection: "Retry connection"
        case .continueGPSOnly: "Continue GPS-only"
        case .retrySave: "Retry save"
        case .finishRecording: "Finish recording"
        case .retryTransfer: "Retry transfer"
        case .checkProcessingReceipt: "Check processing receipt"
        case .chooseCorrectVehicle: "Choose correct vehicle"
        case .restoreBackup: "Restore backup"
        case .openPreservedOriginal: "Open preserved original"
        case .chooseWritableLocation: "Choose writable location"
        case .resumeIngestion: "Resume ingestion"
        case .fitAvailableRoute: "Fit available route"
        case .viewCoverageDetails: "View coverage details"
        case .addFuel: "Add fuel"
        case .attachReceipt: "Attach receipt"
        case .addRecording: "Add recording"
        case .configureDestination: "Configure Mac destination"
        case .reconnectScanner: "Reconnect scanner"
        case .reviewSuggestion: "Review suggestion"
        }
    }
}

public struct DriveLineStateDescriptor: Identifiable, Equatable, Sendable, Codable {
    public var id: Int
    public var category: String
    public var title: String
    public var platform: DriveLineStatePlatform
    public var state: DriveLineSemanticState
    public var trigger: String
    public var persistedEvidence: String
    public var wording: String
    public var actions: [DriveLineRecoveryAction]
    public var recoveryResult: String

    public init(id: Int, category: String, title: String, platform: DriveLineStatePlatform,
                state: DriveLineSemanticState, trigger: String, persistedEvidence: String,
                wording: String, actions: [DriveLineRecoveryAction] = [], recoveryResult: String) {
        self.id=id; self.category=category; self.title=title; self.platform=platform
        self.state=state; self.trigger=trigger; self.persistedEvidence=persistedEvidence
        self.wording=wording; self.actions=actions; self.recoveryResult=recoveryResult
    }
}

/// Normative Phase 8 matrix. Both apps select from these descriptors so the
/// state word, preservation claim, and available recovery action stay aligned.
public enum DriveLineStateMatrix {
    private typealias Row = (Int, String, DriveLineSemanticState)

    public static let all: [DriveLineStateDescriptor] = {
        var rows: [(String, DriveLineStatePlatform, Row)] = []
        func add(_ category: String, _ platform: DriveLineStatePlatform, _ values: [Row]) {
            rows += values.map { (category, platform, $0) }
        }
        add("Empty", .shared, [
            (1,"No vehicles configured",.unavailable),(2,"Vehicle configured with no recordings",.ready),
            (3,"Recording without GPS route",.unavailable),(4,"Recording without scanner telemetry",.unavailable),
            (5,"No fills",.ready),(6,"No receipt attachment",.unavailable),
            (7,"No signals for selected recording",.unavailable),(8,"Known signal unavailable",.unavailable),
            (9,"No comparison candidate",.unavailable),(10,"Archived vehicle with readable history",.readOnly),
            (11,"Empty Mac import queue",.ready),(12,"Empty transfer queue",.ready)
        ])
        add("Recording preflight", .iPhone, [
            (13,"Location permission not determined",.waiting),(14,"Location permission denied",.unavailable),
            (15,"Location permission restricted",.unavailable),(16,"GPS waiting for first acceptable fix",.waiting),
            (17,"GPS available",.ready),(18,"Scanner not configured",.unavailable),
            (19,"Scanner configured but unavailable",.offline),(20,"Scanner connecting",.processing),
            (21,"Scanner authentication or pairing failure",.failed),(22,"Scanner timeout",.failed),
            (23,"Scanner connected to selected vehicle",.ready),(24,"Scanner connected to a different vehicle",.degraded),
            (25,"Local storage unavailable or unwritable",.failed),(26,"Insufficient free-space warning",.degraded),
            (27,"Active recording already exists",.active),(28,"Vehicle switch blocked by active recording",.active)
        ])
        add("Active recording", .iPhone, [
            (29,"Scanner lost while GPS continues",.degraded),(30,"Scanner reconnecting inside grace period",.processing),
            (31,"Scanner recovered inside grace period",.recovered),(32,"Scanner not recovered before grace deadline",.degraded),
            (33,"GPS lost while scanner continues",.degraded),(34,"GPS recovered after a route gap",.recovered),
            (35,"GPS and scanner temporarily unavailable",.degraded),(36,"App backgrounded during active recording",.active),
            (37,"Interrupted recording with recoverable draft",.recovered),(38,"Recovered draft with complete local evidence",.recovered),
            (39,"Recovered draft with known final gap",.recovered),(40,"Finish waiting for persistence write",.processing),
            (41,"Duplicate Finish action",.processing),(42,"Failed final write with draft retained",.failed)
        ])
        add("Offline and transfer", .shared, [
            (43,"Offline with recording preserved locally",.offline),(44,"Mac destination not configured",.unavailable),
            (45,"Mac configured but unreachable",.offline),(46,"Authentication rejected",.failed),
            (47,"Transfer queued",.queued),(48,"Upload in progress",.processing),
            (49,"Upload acknowledged and processing",.processing),(50,"Processing interrupted by Mac restart",.degraded),
            (51,"Processing recovered and requeued",.recovered),(52,"Transfer failed before acknowledgement",.failed),
            (53,"Processing failed after acknowledgement",.failed),(54,"Receipt polling timeout",.stale),
            (55,"Receipt identity mismatch",.failed),(56,"Exact duplicate transfer",.complete),
            (57,"Stable identity with conflicting bytes",.failed),(58,"Transfer processed successfully",.complete),
            (59,"Original retained on iPhone after success",.complete),(60,"Retry with frozen payload",.ready)
        ])
        add("Import and original preservation", .mac, [
            (61,"Unsupported file type",.failed),(62,"Malformed archive",.failed),(63,"Schema too new",.readOnly),
            (64,"Schema-1 legacy archive decoded",.recovered),(65,"Schema-2 archive decoded",.ready),
            (66,"Duplicate content hash",.complete),(67,"Identity conflict",.failed),(68,"Vehicle mismatch",.failed),
            (69,"Missing receipt attachment",.degraded),(70,"Receipt hash or byte-count mismatch",.failed),
            (71,"Import queued",.queued),(72,"Import processing",.processing),(73,"Import failed with original preserved",.failed),
            (74,"Interrupted import recovered after restart",.recovered),(75,"Import completed with processing receipt",.complete),
            (76,"Ingestion paused",.waiting),(77,"Ingestion resumed",.active)
        ])
        add("Signal and coverage", .shared, [
            (78,"Fresh observation at cursor",.ready),(79,"Stale observation",.stale),(80,"Unavailable observation",.unavailable),
            (81,"Non-finite observation excluded",.unavailable),(82,"Sparse observations",.degraded),(83,"Long recorded gap",.degraded),
            (84,"GPS-only recording",.degraded),(85,"OBD-only recording",.degraded),(86,"Mixed recording with full coverage",.complete),
            (87,"Mixed recording with partial GPS coverage",.degraded),(88,"Mixed recording with partial scanner coverage",.degraded),
            (89,"Distance alignment unavailable",.unavailable),(90,"Derived boost unavailable",.unavailable),
            (91,"Normalized DPF trigger",.ready),(92,"Unknown signal identifier",.unavailable)
        ])
        add("Library and storage recovery", .shared, [
            (93,"Missing state or library file",.ready),(94,"Empty new library",.ready),(95,"Corrupt state or library JSON",.readOnly),
            (96,"Unsupported future platform-state schema",.readOnly),(97,"Interrupted atomic state replacement",.recovered),
            (98,"Backup state available",.ready),(99,"Backup successfully restored",.recovered),(100,"Backup also invalid",.failed),
            (101,"Library directory read-only",.readOnly),(102,"Originals directory missing",.degraded),
            (103,"Receipt directory missing",.degraded),(104,"Individual external receipt missing",.unavailable),
            (105,"State references unavailable attachment",.degraded),(106,"Migration failure",.readOnly),
            (107,"Vehicle reference missing or inconsistent",.degraded),(108,"Selected vehicle no longer available",.degraded),
            (109,"Storage path temporarily unavailable",.offline),(110,"Server port conflict or start failure",.failed)
        ])
        add("Mac lifecycle", .mac, [
            (111,"Main window open",.active),(112,"Main window closed while server continues",.active),
            (113,"Ingestion active",.active),(114,"Ingestion paused",.waiting),(115,"App quitting",.processing),
            (116,"Server stopped after quit",.complete),(117,"Server failed to start",.failed),
            (118,"LAN access unavailable",.offline),(119,"Local-only server available",.ready)
        ])
        return rows.sorted { $0.2.0 < $1.2.0 }.map { category, platform, row in
            descriptor(id: row.0, title: row.1, state: row.2, category: category, platform: platform)
        }
    }()

    public static func state(_ id: Int) -> DriveLineStateDescriptor? { all.first { $0.id == id } }

    private static func descriptor(id: Int, title: String, state: DriveLineSemanticState,
                                   category: String, platform: DriveLineStatePlatform) -> DriveLineStateDescriptor {
        DriveLineStateDescriptor(id:id, category:category, title:title, platform:platform, state:state,
            trigger:trigger(id,title), persistedEvidence:evidence(id), wording:wording(id,title,state),
            actions:actions(id), recoveryResult:recovery(id,state))
    }

    private static func trigger(_ id: Int, _ title: String) -> String {
        switch id {
        case 13...17: "Current Core Location authorization and accepted-fix state"
        case 18...24,29...35: "Current scanner/GPS runtime state for the selected vehicle"
        case 37...42: "Persisted recording-draft and final-write state"
        case 43...60: "Persisted transfer item, acknowledgement, and processing receipt"
        case 61...77: "Import receipt, preserved-original, parser, and ingestion state"
        case 78...92: "Recorded observations evaluated at the selected cursor and range"
        case 93...109: "Filesystem, schema, attachment, and backup validation"
        case 110...119: "Mac server, ingestion, window, and application lifecycle"
        default: title
        }
    }

    private static func evidence(_ id: Int) -> String {
        switch id {
        case 1...12: "Existing vehicle, recording, fill, receipt, queue, and archive records"
        case 13...17: "Authorization value and accepted GPS fix timestamp; no location is invented"
        case 18...24: "Per-vehicle scanner configuration, runtime vehicle UUID, and connection result; secrets excluded"
        case 25...28: "Writable-store result and the original vehicle-bound draft"
        case 29...42: "Checkpointed draft, source timestamps, gap boundary, fixed end request, and source-specific observations"
        case 43...60: "Locally saved recording, immutable payload bytes/hash, destination acknowledgement, and processing receipt"
        case 61...77: "Copied original bytes/hash, import receipt, stable identities, external attachment metadata, and processing result"
        case 78...92: "Finite recorded values, real timestamps, source IDs, provenance, coverage, and explicit gaps"
        case 93...109: "Original state bytes, validated backup when present, directories, references, and schema number"
        default: "Actual application, ingestion, listener, and shutdown state"
        }
    }

    private static func wording(_ id: Int, _ title: String, _ state: DriveLineSemanticState) -> String {
        switch id {
        case 3: "No GPS route was recorded. Scanner evidence remains available."
        case 4: "No scanner telemetry was recorded. The GPS route remains available."
        case 6: "No receipt is attached. The fuel entry remains saved."
        case 8: "This signal was not observed in the selected recording."
        case 18: "No scanner is configured for this vehicle. GPS-only recording remains available."
        case 24: "The scanner is connected to a different vehicle. Recording is blocked to prevent misassignment."
        case 26: "Storage may be too low for reliable recording; DriveLine cannot promise an exact remaining recording time."
        case 29: "Scanner unavailable; GPS continues recording locally during the existing grace period."
        case 30: "Reconnecting scanner; GPS continues and failed attempts do not extend the original deadline."
        case 31: "Scanner recovered. The interruption remains visible as a recorded gap."
        case 32: "Scanner did not recover before the deadline. The recording ends at the last scanner evidence."
        case 33: "GPS unavailable; scanner telemetry continues and the route retains a visible gap."
        case 34: "GPS recovered. The missing route interval remains visible and is not bridged."
        case 35: "Both sources are unavailable. The checkpointed draft remains saved; no samples are fabricated."
        case 37: "An interrupted draft was found and recovered once from its checkpointed evidence."
        case 39: "The draft was recovered, but its known final interval is missing and remains identified as a gap."
        case 42: "The final write failed. The only recoverable draft and fixed end boundary are retained for retry."
        case 43: "Offline. The recording is saved locally and has not been transferred."
        case 47: "Queued with immutable payload bytes and content hash."
        case 48: "Uploading preserved bytes; bytes sent does not mean transferred or processed."
        case 49: "The Mac acknowledged storage of the original and is still processing it."
        case 52: "Transfer failed before destination acknowledgement. The frozen local payload is preserved."
        case 53: "The Mac acknowledged the original, but processing failed there."
        case 54: "Receipt polling timed out; destination processing completion is unknown."
        case 55: "The returned receipt identity does not match this transfer; completion was not recorded."
        case 56: "Exact bytes already have an authoritative destination receipt; no duplicate is created."
        case 57: "The stable identity exists with different bytes. Neither original is overwritten."
        case 58: "The destination acknowledged and confirmed processing completion."
        case 59: "Transfer is complete and the original remains on this iPhone."
        case 60: "Retry sends the identical frozen payload without rebuilding or mutating it."
        case 62: "The archive is malformed. Its original bytes remain preserved and no partial data was committed."
        case 63,96: "This data needs a newer app. It remains preserved unchanged in read-only recovery state."
        case 64: "Legacy schema-1 data decoded through the version-2 adapter without rewriting the original."
        case 66: "The content hash matches an existing receipt. No duplicate data is created."
        case 67: "A stable identity conflicts with different preserved bytes; existing data is not overwritten."
        case 68: "The archive vehicle identity differs from the target. Data is not reassigned."
        case 69,104: "Receipt metadata remains preserved, but the external receipt file is unavailable."
        case 70: "Receipt bytes do not match their SHA-256 or byte count and were not installed."
        case 71: "Queued only after the original was durably preserved."
        case 72: "Processing the preserved original; library state changes only after a successful parse."
        case 73: "Import failed. The original remains preserved for a targeted retry."
        case 74: "Interrupted processing was requeued after restart using the same receipt and original."
        case 75: "Import committed with a processing receipt and preserved original."
        case 79: "The last observation is outside its freshness interval at this cursor."
        case 80: "No recorded observation is available at this cursor."
        case 81: "A non-finite observation is retained as source evidence but excluded from displayed statistics."
        case 82: "Only the sparse recorded points are shown; no sample rate is inferred."
        case 83: "The chart breaks across this recorded gap; values are not forward-filled or interpolated."
        case 84: "GPS evidence is available. OBD coverage is unavailable and not implied."
        case 85: "OBD evidence is available. GPS route and distance alignment are unavailable."
        case 90: "Gauge boost is unavailable because compatible fresh barometric evidence is missing."
        case 91: "Normalized DPF regeneration trigger indicator; never physical soot, ash, or filter fullness."
        case 92: "The raw stable identifier is shown; display name, unit, and scaling are unavailable."
        case 95: "The library cannot be decoded. Original unreadable bytes are preserved and never replaced by an empty library."
        case 97: "An interrupted atomic replacement was detected; the primary and last valid backup remain preserved."
        case 99: "The validated backup was restored after the damaged source was preserved."
        case 100: "The primary and backup are invalid. Both remain preserved; no empty reset is created."
        case 101: "The library is readable but not writable. Safe history remains available read-only."
        case 106: "Migration failed before commit. Pre-migration bytes remain preserved."
        case 107: "Data references a missing vehicle UUID. It remains retained and is not reassigned or cascade-deleted."
        case 112: "The main window is closed while the currently running local server continues; quitting still stops it."
        case 115: "DriveLine is quitting and stopping local services; no background service is promised afterward."
        case 118: "LAN access is unavailable. Local-only service may remain available when actually listening."
        case 119: "The server is available on this Mac only; LAN reachability is not claimed."
        default: "\(state.title): \(title). Existing evidence remains preserved."
        }
    }

    private static func actions(_ id: Int) -> [DriveLineRecoveryAction] {
        switch id {
        case 1,94: [.configureVehicle]
        case 2: [.addRecording]
        case 5: [.addFuel]
        case 6: [.attachReceipt]
        case 3,4,7,8,78...92: [.viewCoverageDetails]
        case 13...15,21,110,117,118: [.openSettings]
        case 18,19,22: [.retryConnection,.continueGPSOnly]
        case 24,68,107,108: [.chooseCorrectVehicle]
        case 25,101...103,109: [.chooseWritableLocation]
        case 27...30,33,35,36: [.finishRecording]
        case 42: [.retrySave]
        case 97...100,106: [.restoreBackup,.retrySave]
        case 43,45...48,52,60: [.retryTransfer]
        case 44: [.configureDestination]
        case 49...51,53...55: [.checkProcessingReceipt]
        case 57,62,63,66,67,70,73: [.openPreservedOriginal]
        case 76,114: [.resumeIngestion]
        default: []
        }
    }

    private static func recovery(_ id: Int, _ state: DriveLineSemanticState) -> String {
        switch id {
        case 29...35: "Available sources continue; outage intervals remain explicit gaps."
        case 37...42: "The same draft identity and evidenced end boundary are retained."
        case 43...60: "Local originals and frozen payload bytes are never deleted or rebuilt by retry."
        case 61...77: "Import recovery uses the preserved original and existing receipt identity."
        case 78...92: "Only recorded finite observations contribute to values, coverage, and statistics."
        case 93...109: "No vehicles, fills, receipts, drafts, preferences, originals, or queues are reset."
        case 110...119: "The displayed state follows the actual process and listener lifecycle."
        default: "The state advances only after the described result is verified; current evidence remains intact."
        }
    }
}
