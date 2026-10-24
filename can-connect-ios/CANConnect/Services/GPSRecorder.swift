import CoreLocation
import Combine

@MainActor
final class GPSRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var speedKMH: Double?
    @Published var lastFix: Date?
    @Published var status = "Ready when you are"
    var onPoint: ((RoutePoint) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private let manager = CLLocationManager()
    private var wantsRecording = false
    private var updatesBeganAt: Date?
    // Core Location delivers delegate calls on the run loop where its manager was created.
    // This manager is created on the main actor; the conformance checks that at runtime.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }
    func start() {
        wantsRecording = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .notDetermined: status = "Waiting for permission"; manager.requestWhenInUseAuthorization()
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
        status = "Ready when you are"
    }
    private func beginUpdates() {
        guard wantsRecording, updatesBeganAt == nil else { return }
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
    private func fail(_ message: String) { stop(); status = message; onFailure?(message) }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsRecording else { return }
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
            onPoint?(RoutePoint(latitude:location.coordinate.latitude, longitude:location.coordinate.longitude, timestamp:location.timestamp, accuracy:location.horizontalAccuracy, speed:location.speed >= 0 ? location.speed : nil))
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
