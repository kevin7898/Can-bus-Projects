import Foundation

struct PhoneTodayPresentation: Equatable {
    enum Readiness: Equatable { case ready, needsVehicle, sampleVehicle }

    var date: Date
    var vehicleTitle: String?
    var readiness: Readiness
    var gpsStatus: String
    var scannerStatus: String
    var scannerConnected: Bool
    var scannerConnecting: Bool
    var queuedTransfers: Int
    var todayDriveCount: Int
    var todayDistanceKM: Double
    var todayDuration: TimeInterval
    var todayFuelLitres: Double?
    var todayFuelDriveCount: Int
    var latestTrip: Trip?
    var latestFill: FuelEntry?

    static func make(state: StoredState, now: Date, calendar: Calendar = .current,
                     gpsStatus: String, scannerStatus: String,
                     scannerConnected: Bool, scannerConnecting: Bool) -> Self {
        let vehicle = state.vehicles.first { $0.id == state.selectedVehicleID }
        let realTrips = state.trips.filter { $0.vehicleID == state.selectedVehicleID && !$0.isSample }.sorted { $0.startedAt > $1.startedAt }
        let todayTrips = realTrips.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
        let measuredFuel = todayTrips.compactMap(\.fuelLitres)
        let latestFill = state.fills.filter { $0.vehicleID == state.selectedVehicleID && !$0.isSample }.max { $0.date < $1.date }
        let queued = state.transfers.filter { $0.status == .queued || $0.status == .awaitingReceipt }.count
        let readiness: Readiness = vehicle == nil ? .needsVehicle : (vehicle?.isSample == true ? .sampleVehicle : .ready)
        return Self(date:now, vehicleTitle:vehicle?.title, readiness:readiness,
                    gpsStatus:gpsStatus, scannerStatus:scannerStatus,
                    scannerConnected:scannerConnected, scannerConnecting:scannerConnecting,
                    queuedTransfers:queued, todayDriveCount:todayTrips.count,
                    todayDistanceKM:todayTrips.reduce(0) { $0 + $1.distanceKM },
                    todayDuration:todayTrips.reduce(0) { $0 + $1.duration },
                    todayFuelLitres:measuredFuel.isEmpty ? nil : measuredFuel.reduce(0,+),
                    todayFuelDriveCount:measuredFuel.count, latestTrip:realTrips.first, latestFill:latestFill)
    }
}
