import CoreLocation
import Combine
import UIKit

/// NotificationCenter's opaque Objective-C token is thread-safe to remove but
/// is not annotated Sendable. Owning it in this small wrapper keeps actor-owned
/// services from reaching into a non-Sendable token during nonisolated deinit.
final class MainThreadNotificationObservation: @unchecked Sendable {
    private let token:NSObjectProtocol
    init(_ token:NSObjectProtocol) { self.token=token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

enum GPSPermissionState:Equatable { case notDetermined,denied,restricted,available }

@MainActor
protocol GPSRecording: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var speedKMH: Double? { get }
    var lastFix: Date? { get }
    var status: String { get }
    var permissionState:GPSPermissionState { get }
    var onPoint: ((RoutePoint) -> Void)? { get set }
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func requestAutomaticAuthorization()
    func start()
    func stop()
}

extension GPSRecording { var permissionState:GPSPermissionState { .available } }

@MainActor
final class GPSRecorder: NSObject, ObservableObject, GPSRecording, @preconcurrency CLLocationManagerDelegate {
    @Published var speedKMH: Double?
    @Published var lastFix: Date?
    @Published var status = "Ready when you are"
    var onPoint: ((RoutePoint) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private let manager: CLLocationManager
    private let isForeground: @MainActor () -> Bool
    private var foregroundObserver: MainThreadNotificationObservation?
    private var upgradeAfterPermission = false
    private var wantsRecording = false
    var permissionState:GPSPermissionState {
        switch manager.authorizationStatus {
        case .notDetermined:return .notDetermined
        case .denied:return .denied
        case .restricted:return .restricted
        default:return .available
        }
    }
    private var updatesBeganAt: Date?
    // Core Location delivers delegate calls on the run loop where its manager was created.
    // This manager is created on the main actor; the conformance checks that at runtime.
    init(manager: CLLocationManager = CLLocationManager(),
         isForeground: (@MainActor () -> Bool)? = nil) {
        self.manager = manager
        self.isForeground = isForeground ?? { UIApplication.shared.applicationState == .active }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        foregroundObserver = MainThreadNotificationObservation(NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.resumeIfRequested() }
        })
        updateIdleStatus()
    }
    func requestAutomaticAuthorization() {
        guard isForeground() else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            upgradeAfterPermission = true; manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        default: resumeIfRequested()
        }
    }
    private func updateIdleStatus() {
        status = manager.authorizationStatus == .authorizedAlways ? "Automatic trip GPS ready" : "Automatic GPS needs Always access · tap to enable"
    }
    private func resumeIfRequested() {
        if wantsRecording { start() } else { updateIdleStatus() }
    }
    func start() {
        wantsRecording = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .notDetermined:
            status = "Open DriveLine to allow GPS access"
            if isForeground() { manager.requestWhenInUseAuthorization() }
        default: fail("Allow location access in iPhone Settings to record a GPS drive.")
        }
    }
    func stop() {
        wantsRecording = false
        updatesBeganAt = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        speedKMH = nil
        lastFix = nil
        updateIdleStatus()
    }
    private func beginUpdates() {
        guard wantsRecording, updatesBeganAt == nil else { return }
        // When In Use can continue an existing foreground session, but cannot
        // reliably start a new session for an automatic background scanner trip.
        guard manager.authorizationStatus == .authorizedAlways || isForeground() else {
            status = "GPS waiting · open DriveLine or enable Always access"
            return
        }
        updatesBeganAt = Date()
        // A cached pre-recording fix must not strand a stationary recording behind
        // the movement filter. Restore the filter after obtaining a fresh point.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        status = "Waiting for a GPS fix"
        onReady?()
        manager.startUpdatingLocation()
    }
    private func fail(_ message: String) {
        // Keep the recording intent so a permission change/foreground return can
        // resume GPS for an ongoing scanner trip. Finish still calls stop().
        manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
        updatesBeganAt = nil; speedKMH = nil; lastFix = nil
        status = message; onFailure?(message)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if upgradeAfterPermission && manager.authorizationStatus == .authorizedWhenInUse && isForeground() {
            upgradeAfterPermission = false; manager.requestAlwaysAuthorization()
        }
        guard wantsRecording else { updateIdleStatus(); return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted: fail("Location access is off. Enable it in Settings to record a drive.")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsRecording, let updatesBeganAt else { return }
        for location in locations where Self.acceptsFix(timestamp:location.timestamp,accuracy:location.horizontalAccuracy,beganAt:updatesBeganAt,now:Date()) {
            manager.distanceFilter = 5
            lastFix = location.timestamp
            speedKMH = location.speed >= 0 && location.speed <= 80 ? location.speed * 3.6 : nil
            status = "GPS active · ±\(Int(location.horizontalAccuracy)) m"
            onPoint?(RoutePoint(latitude:location.coordinate.latitude, longitude:location.coordinate.longitude, timestamp:location.timestamp, accuracy:location.horizontalAccuracy, speed:location.speed >= 0 && location.speed <= 80 ? location.speed : nil))
        }
    }
    nonisolated static func acceptsFix(timestamp: Date, accuracy: Double, beganAt: Date, now: Date) -> Bool {
        timestamp >= beganAt && abs(timestamp.timeIntervalSince(now)) < 15 && accuracy.isFinite && (0...50).contains(accuracy)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { status = "Waiting for a GPS fix"; speedKMH = nil }
        else { fail(error.localizedDescription) }
    }
}
