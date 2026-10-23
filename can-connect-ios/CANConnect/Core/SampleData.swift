import Foundation

enum SampleData {
    static let routeCoordinates: [[Double]] = [[49.1654,-123.9401],[49.1683,-123.9454],[49.1740,-123.9507],[49.1795,-123.9550],[49.1847,-123.9551],[49.1898,-123.9514],[49.1934,-123.9495],[49.1957,-123.9543]]
    static func route(date: Date = Date()) -> [RoutePoint] {
        routeCoordinates.enumerated().map { i, c in RoutePoint(latitude:c[0], longitude:c[1], timestamp:date.addingTimeInterval(Double(i) * 60), accuracy:5, speed:18) }
    }
    static func state(now: Date = Date()) -> StoredState {
        let specs: [(String, Double, Double, Double?, TripSource)] = [
            ("Nanaimo → Departure Bay",24.8,34,5.4,.imported),
            ("Departure Bay → Nanaimo",23.6,31,nil,.phoneGPS),
            ("Nanaimo evening loop",38.2,46,5.7,.imported),
            ("Bowen Road errands",12.7,25,nil,.phoneGPS),
            ("Morning drive",15.2,22,5.3,.imported)]
        let vehicle = VehicleProfile.sample
        let trips = specs.enumerated().map { i, s in
            let date = now.addingTimeInterval(-Double(i + 1) * 19_800)
            return Trip(vehicleID:vehicle.id, name:s.0, startedAt:date, duration:s.2 * 60, distanceKM:s.1, source:s.4, isSample:true, economy:s.3, fuelLitres:s.3.map { s.1 * $0 / 100 }, route:route(date:date))
        }
        let fill = FuelEntry(vehicleID:vehicle.id, date:now.addingTimeInterval(-259_200), litres:46.2, costCAD:79.46, odometerKM:216274, full:true, isSample:true)
        return StoredState(vehicles:[vehicle], selectedVehicleID:vehicle.id, trips:trips, fills:[fill])
    }
}
