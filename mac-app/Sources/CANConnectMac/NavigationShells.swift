import SwiftUI

struct DrivesDestinationView:View {
    @State private var comparison=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Picker("Drives mode",selection:$comparison) {
                    Text("Ledger").tag(false)
                    Text("Compare").tag(true)
                }.pickerStyle(.segmented).frame(width:220).accessibilityIdentifier("mac.drives.mode")
                Spacer()
                if comparison { Label("Compare uses the same preserved recordings",systemImage:"rectangle.split.2x1").foregroundStyle(Theme.secondaryText) }
            }.font(.system(size:11))
            if comparison { CompareView() } else { TripsView() }
        }
    }
}

struct FuelDestinationView:View {
    @EnvironmentObject private var store:AppStore
    var entries:[FuelEntry] { store.state.fuelEntries.filter { $0.vehicleID==store.state.selectedVehicleID }.sorted { $0.date>$1.date } }
    var body:some View {
        if entries.isEmpty {
            EmptyPanel(title:"No fuel entries yet",message:"Imported and transferred fills for the selected vehicle will appear here. Purchased quantity remains separate from measured trip fuel.")
        } else {
            Panel(title:"Fuel ledger · \(entries.count) fills",icon:"fuelpump") {
                ForEach(entries) { entry in
                    HStack(spacing:14) {
                        Image(systemName:"fuelpump.fill").foregroundStyle(Theme.fuelAttention)
                        VStack(alignment:.leading,spacing:4) {
                            Text(entry.stationName ?? "Fuel fill").font(.system(size:12,weight:.semibold))
                            Text(entry.date.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text("\(number(entry.litresPurchased)) L purchased").monospacedDigit()
                        Text(entry.totalCost.formatted(.currency(code:entry.currencyCode))).monospacedDigit()
                        if entry.receipt != nil { Label("Receipt",systemImage:"doc.text").foregroundStyle(Theme.healthy) }
                    }.font(.system(size:11)).padding(13)
                    Divider().overlay(Theme.border)
                }
            }
        }
    }
}
