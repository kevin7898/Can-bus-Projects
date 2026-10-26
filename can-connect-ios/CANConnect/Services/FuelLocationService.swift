import CoreLocation
import Foundation

@MainActor
final class FuelLocationService:NSObject,FuelLocationProviding,@preconcurrency CLLocationManagerDelegate {
    private let manager:CLLocationManager
    private let geocoder:CLGeocoder
    private var continuation:CheckedContinuation<CLLocation,Error>?
    private var timeoutTask:Task<Void,Never>?
    private var cachedSuggestion:FuelStationSuggestion?

    init(manager:CLLocationManager=CLLocationManager(),geocoder:CLGeocoder=CLGeocoder()) {
        self.manager=manager;self.geocoder=geocoder
        super.init();manager.delegate=self;manager.desiredAccuracy=kCLLocationAccuracyNearestTenMeters
    }

    func currentStation() async throws ->FuelStationSuggestion {
        if manager.authorizationStatus == .denied { throw FuelLocationFailure.permissionDenied }
        if manager.authorizationStatus == .restricted { throw FuelLocationFailure.restricted }
        if let cachedSuggestion,(0...60).contains(Date().timeIntervalSince(cachedSuggestion.observedAt)) { return cachedSuggestion }
        let location=try await requestLocation()
        let geocodeTimeout=Task { [weak self] in
            try? await Task.sleep(for:.seconds(8))
            guard !Task.isCancelled else { return }
            self?.geocoder.cancelGeocode()
        }
        defer { geocodeTimeout.cancel() }
        do {
            let placemarks=try await withTaskCancellationHandler(operation:{
                try await geocoder.reverseGeocodeLocation(location)
            },onCancel:{ Task { @MainActor [weak self] in self?.geocoder.cancelGeocode() } })
            try Task.checkCancellation()
            guard let placemark=placemarks.first else { throw FuelLocationFailure.noResult }
            let address=Self.formattedAddress(placemark)
            guard !address.isEmpty else { throw FuelLocationFailure.noResult }
            let suggestion=FuelStationSuggestion(stationName:Self.confidentStationName(placemark),stationAddress:address,
                observedAt:location.timestamp)
            cachedSuggestion=suggestion;return suggestion
        } catch let failure as FuelLocationFailure { throw failure }
        catch let error as CLError where error.code == .network { throw FuelLocationFailure.offline }
        catch let error as CLError where error.code == .geocodeCanceled { throw FuelLocationFailure.timeout }
        catch { throw FuelLocationFailure.noResult }
    }

    private func requestLocation() async throws ->CLLocation {
        guard continuation == nil else { throw FuelLocationFailure.unavailable }
        switch manager.authorizationStatus {
        case .denied:throw FuelLocationFailure.permissionDenied
        case .restricted:throw FuelLocationFailure.restricted
        default:break
        }
        if let location=manager.location,Self.accepts(location,now:Date()) { return location }
        return try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation { continuation in
                self.continuation=continuation
                self.timeoutTask=Task { [weak self] in
                    try? await Task.sleep(nanoseconds:8_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(FuelLocationFailure.timeout))
                }
                if self.manager.authorizationStatus == .notDetermined { self.manager.requestWhenInUseAuthorization() }
                else { self.manager.requestLocation() }
            }
        },onCancel:{ Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } })
    }

    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:manager.requestLocation()
        case .denied:finish(.failure(FuelLocationFailure.permissionDenied))
        case .restricted:finish(.failure(FuelLocationFailure.restricted))
        default:break
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location=locations.filter({Self.accepts($0,now:Date())}).min(by:{$0.horizontalAccuracy<$1.horizontalAccuracy}) else {
            finish(.failure(FuelLocationFailure.unavailable));return
        }
        finish(.success(location))
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) {
        if let code=(error as? CLError)?.code,code == .denied { finish(.failure(FuelLocationFailure.permissionDenied)) }
        else { finish(.failure(FuelLocationFailure.unavailable)) }
    }
    private func finish(_ result:Result<CLLocation,Error>) {
        guard let continuation else { return }
        self.continuation=nil;timeoutTask?.cancel();timeoutTask=nil
        continuation.resume(with:result)
    }
    nonisolated static func accepts(_ location:CLLocation,now:Date)->Bool {
        location.horizontalAccuracy.isFinite && (0...100).contains(location.horizontalAccuracy) &&
        (0...120).contains(now.timeIntervalSince(location.timestamp))
    }
    nonisolated static func formattedAddress(_ placemark:CLPlacemark)->String {
        var parts:[String]=[]
        let street=[placemark.subThoroughfare,placemark.thoroughfare].compactMap{$0}.joined(separator:" ")
        if !street.isEmpty { parts.append(street) }
        parts.append(contentsOf:[placemark.locality,placemark.administrativeArea,placemark.postalCode].compactMap{$0}.filter{!$0.isEmpty})
        return parts.joined(separator:", ")
    }
    nonisolated static func confidentStationName(_ placemark:CLPlacemark)->String? {
        // A reverse-geocoded name/area-of-interest is not a verified fuel POI
        // category (for example, "Gas Works Museum"). Address is trustworthy;
        // retain manual station-name entry until category evidence is available.
        nil
    }
}
