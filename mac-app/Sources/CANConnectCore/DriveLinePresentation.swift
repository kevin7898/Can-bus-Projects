import Foundation

public struct MacTodayPresentation {
    public var date:Date
    public var vehicle:Vehicle?
    public var todayTrips:[Trip]
    public var recentTrips:[Trip]
    public var latestTrip:Trip?
    public var latestFill:FuelEntry?
    public var todayDistanceKm:Double?
    public var todayDuration:TimeInterval
    public var todayFuelLitres:Double?
    public var fuelTripCount:Int
    public var queuedImports:Int

    public static func make(state:LibraryState,now:Date,calendar:Calendar = .current)->Self {
        let vehicle=state.vehicles.first { $0.id==state.selectedVehicleID }
        let realTrips=state.trips.filter { $0.vehicleID==state.selectedVehicleID && !$0.isDemo }.sorted { $0.start>$1.start }
        let today=realTrips.filter { calendar.isDate($0.start,inSameDayAs:now) }
        let distances=today.compactMap(\.distanceKm), fuel=today.compactMap(\.fuelUsedL)
        let fill=state.fuelEntries.filter { $0.vehicleID==state.selectedVehicleID && !$0.isDemo }.max { $0.date<$1.date }
        return Self(date:now,vehicle:vehicle,todayTrips:today,recentTrips:Array(realTrips.prefix(4)),latestTrip:realTrips.first,latestFill:fill,
                    todayDistanceKm:distances.isEmpty ? nil:distances.reduce(0,+),todayDuration:today.reduce(0){$0+$1.duration},
                    todayFuelLitres:fuel.isEmpty ? nil:fuel.reduce(0,+),fuelTripCount:fuel.count,
                    queuedImports:state.receipts.filter{$0.status == .queued || $0.status == .processing}.count)
    }
}
