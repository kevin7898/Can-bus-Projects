import SwiftUI

struct FuelRangeCard:View {
    @UnitPreferences private var units
    @EnvironmentObject private var store:AppStore
    var vehicleID:UUID?
    @State private var history=RollingFuelWindow()
    @State private var historyVehicleID:UUID?
    @State private var loading=true
    private var vehicle:VehicleProfile? { store.state.vehicles.first { $0.id == vehicleID && !$0.isSample } }
    private var window:RollingFuelWindow {
        let base=historyVehicleID == vehicleID ? history:RollingFuelWindow()
        return store.state.draft?.vehicleID == vehicleID ? base.appending(store.liveFuelWindow):base
    }
    private var fuel:Double? {
        guard store.scanner.vehicleID == vehicleID else { return nil }
        return store.scanner.value("clusterFuelLitres",at:Date())
    }
    private struct LoadKey:Equatable { var vehicleID:UUID?;var trips:[Trip] }
    var body:some View {
        if let vehicle {
            SectionCard(title:"Fuel & range · test",icon:"fuelpump") {
                DataRow(label:"Cluster fuel estimate",value:fuel.map { units.text($0,"L",digits:2) } ?? "Unavailable or stale")
                DataRow(label:"Range before reserve",value:window.range(fuel:fuel,reserve:vehicle.reserveLitres).map { "≈ \(units.text($0,"km",digits:0))" } ?? "Learning / awaiting fuel")
                DataRow(label:"Rolling consumption",value:window.economy.map { units.text($0,"L/100 km",digits:2) } ?? "Needs 1 km of matched data")
                Text(loading ? "Preparing recorded driving…":"Based on \(units.number(window.km,"km")) of \(units.text(500,"km",digits:0)) with matched fuel and speed data. \(window.km < 500 ? "Learning as you drive.":"Oldest driving rolls out as new driving arrives.")")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                Stepper(value:Binding(get:{vehicle.reserveLitres},set:{store.setFuelReserve($0,vehicleID:vehicle.id)}),in:0...50,step:0.5) {
                    Text("Keep \(units.text(vehicle.reserveLitres,"L",digits:2)) in reserve")
                }.accessibilityIdentifier("fuel.reserve")
                if store.scanner.vehicleID == vehicleID,let odo=store.scanner.value("clusterOdometerCoarseKM",at:Date()) {
                    DataRow(label:"Experimental odometer",value:"\(units.text(odo,"km",digits:0)) · coarse")
                }
                Text("Cluster reads about once a minute. Fuel volume and range are estimates; reserve is your buffer. The odometer candidate appears to change in 10 km steps and is not used for distance or fill-up odometer entry.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            .task(id:LoadKey(vehicleID:vehicleID,trips:store.state.trips)) {
                loading=true
                do {
                    let result=try await FuelRangeHistory.shared.window(trips:store.state.trips,vehicleID:vehicle.id)
                    try Task.checkCancellation();history=result;historyVehicleID=vehicle.id;loading=false
                } catch { }
            }
        }
    }
}
